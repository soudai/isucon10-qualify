# frozen_string_literal: true

require 'sinatra'
require 'mysql2'
require 'mysql2-cs-bind'
require 'csv'

class App < Sinatra::Base
  LIMIT = 20
  NAZOTTE_LIMIT = 50
  CHAIR_SEARCH_CONDITION = JSON.parse(File.read('../fixture/chair_condition.json'), symbolize_names: true)
  ESTATE_SEARCH_CONDITION = JSON.parse(File.read('../fixture/estate_condition.json'), symbolize_names: true)
  BOT_REGEXP = [
    /ISUCONbot(-Mobile)?/,
    /ISUCONbot-Image\//,
    /Mediapartners-ISUCON/,
    /ISUCONCoffee/,
    /ISUCONFeedSeeker(Beta)?/,
    /crawler \(https:\/\/isucon\.invalid\/(support\/faq\/|help\/jp\/)/,
    /isubot/,
    /Isupider/,
    /Isupider(-image)?\+/,
    /(bot|crawler|spider)(?:[-_ .\/;@()]|$)/i,
  ]

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader
  end

  configure do
    # enable :logging
  end

  before do
    BOT_REGEXP.each do |regexp|
      if regexp.match?(request.user_agent)
        halt 503
      end
    end
  end

  set :add_charset, ['application/json']

  helpers do
    def db_info
      {
        host: ENV.fetch('MYSQL_HOST', '127.0.0.1'),
        port: ENV.fetch('MYSQL_PORT', '3306'),
        username: ENV.fetch('MYSQL_USER', 'isucon'),
        password: ENV.fetch('MYSQL_PASS', 'isucon'),
        database: ENV.fetch('MYSQL_DBNAME', 'isuumo'),
      }
    end

    def db
      Thread.current[:db] ||= Mysql2::Client.new(
        host: db_info[:host],
        port: db_info[:port],
        username: db_info[:username],
        password: db_info[:password],
        database: db_info[:database],
        reconnect: true,
        symbolize_keys: true,
      )
    end

    def transaction(name)
      begin_transaction(name)
      yield(name)
      commit_transaction(name)
    rescue Exception => e
      puts "Failed to commit tx: #{e.inspect}"
      rollback_transaction(name)
      raise
    ensure
      ensure_to_abort_transaction(name)
    end

    def begin_transaction(name)
      Thread.current[:db_transaction] ||= {}
      db.query('BEGIN')
      Thread.current[:db_transaction][name] = :open
    end

    def commit_transaction(name)
      Thread.current[:db_transaction] ||= {}
      db.query('COMMIT')
      Thread.current[:db_transaction][name] = :nil
    end

    def rollback_transaction(name)
      Thread.current[:db_transaction] ||= {}
      db.query('ROLLBACK')
      Thread.current[:db_transaction][name] = :nil
    end

    def ensure_to_abort_transaction(name)
      Thread.current[:db_transaction] ||= {}
      if in_transaction?(name)
        puts "Transaction closed implicitly (#{$$}, #{Thread.current.object_id}): #{name}"
        rollback_transaction(name)
      end
    end

    def in_transaction?(name)
      Thread.current[:db_transaction] && Thread.current[:db_transaction][name] == :open
    end

    def camelize_keys_for_estate(estate_hash)
      e = estate_hash
      e[:doorHeight] = e.delete(:door_height)
      e[:doorWidth] = e.delete(:door_width)
      e
    end

    def body_json_params
      @body_json_params ||= JSON.parse(request.body.tap(&:rewind).read, symbolize_names: true)
    rescue JSON::ParserError => e
      puts "Failed to parse body: #{e.inspect}"
      halt 400
    end
  end

  post '/initialize' do
    starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    sql_dir = Pathname.new('../mysql/db')
    %w[0_Schema.sql 1_EstateData_t.sql 2_ChairData_t.sql 3_EstateFeaturesData.sql 4_ChairFeaturesData.sql].each do |sql|
      sql_path = sql_dir.join(sql)
      cmd = ['mysql', '-h', db_info[:host], '-u', db_info[:username], "-p#{db_info[:password]}", '-P', db_info[:port], db_info[:database]]
      IO.popen(cmd, 'w') do |io|
        io.puts File.read(sql_path)
        io.close
      end
    end

    ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed = ending - starting
    puts "initialize: #{elapsed} seconds"

    { language: 'ruby' }.to_json
  end

  get '/api/chair/low_priced' do
    sql = "SELECT * FROM chair WHERE stock > 0 ORDER BY price ASC, id ASC LIMIT #{LIMIT}" # XXX:
    chairs = db.query(sql).to_a
    { chairs: chairs }.to_json
  end

  get '/api/chair/search' do
    search_queries = []
    query_params = []

    if params[:priceRangeId] && params[:priceRangeId].size > 0
      search_queries << 'price_t = ?'
      query_params << params[:priceRangeId].to_i
    end

    if params[:heightRangeId] && params[:heightRangeId].size > 0
      search_queries << 'height_t = ?'
      query_params << params[:heightRangeId].to_i
    end

    if params[:widthRangeId] && params[:widthRangeId].size > 0
      search_queries << 'width_t = ?'
      query_params << params[:widthRangeId].to_i
    end

    if params[:depthRangeId] && params[:depthRangeId].size > 0
      search_queries << 'depth_t = ?'
      query_params << params[:depthRangeId].to_i
    end

    if params[:kind] && params[:kind].size > 0
      search_queries << 'kind = ?'
      query_params << params[:kind]
    end

    if params[:color] && params[:color].size > 0
      search_queries << 'color = ?'
      query_params << params[:color]
    end

    if params[:features] && params[:features].size > 0
      features = params[:features].split(',')
      ids = db.xquery("SELECT chair_id id, COUNT(*) num FROM chair_features WHERE name IN (?) GROUP BY chair_id HAVING num = ?", features, features.size).map { |r| r[:id] }
      if ids.empty?
        search_queries << "1!=1"
      else
        search_queries << "id IN (?)"
        query_params << ids
      end
    end

    if search_queries.size == 0
      puts "Search condition not found"
      halt 400
    end

    search_queries.push('stock > 0')

    page =
      begin
        Integer(params[:page], 10)
      rescue ArgumentError => e
        puts "Invalid format page parameter: #{e.inspect}"
        halt 400
      end

    per_page =
      begin
        Integer(params[:perPage], 10)
      rescue ArgumentError => e
        puts "Invalid format perPage parameter: #{e.inspect}"
        halt 400
      end

    sqlprefix = 'SELECT * FROM chair WHERE '
    search_condition = search_queries.join(' AND ')
    limit_offset = " ORDER BY popularity DESC, id ASC LIMIT #{per_page} OFFSET #{per_page * page}" # XXX: mysql-cs-bind doesn't support escaping variables for limit and offset
    count_prefix = 'SELECT COUNT(*) as count FROM chair WHERE '

    count = db.xquery("#{count_prefix}#{search_condition}", query_params).first[:count]
    chairs = db.xquery("#{sqlprefix}#{search_condition}#{limit_offset}", query_params).to_a

    { count: count, chairs: chairs }.to_json
  end

  get '/api/chair/:id' do
    id =
      begin
        Integer(params[:id], 10)
      rescue ArgumentError => e
        puts "Request parameter \"id\" parse error: #{e.inspect}"
        halt 400
      end

    chair = db.xquery('SELECT * FROM chair WHERE id = ?', id).first
    unless chair
      puts "Requested id's chair not found: #{id}"
      halt 404
    end

    if chair[:stock] <= 0
      puts "Requested id's chair is sold out: #{id}"
      halt 404
    end

    chair.to_json
  end

  post '/api/chair' do
    if !params[:chairs] || !params[:chairs].respond_to?(:key) || !params[:chairs].key?(:tempfile)
      puts 'Failed to get form file'
      halt 400
    end

    feats = []
    rows  = []
      CSV.parse(params[:chairs][:tempfile].read, skip_blanks: true) do |row|
        #  0,    1,           2,         3,     4,      5,     6,     7,     8,        9,   10,         11,    12
        # id, name, description, thumbnail, price, height, width, depth, color, features, kind, popularity, stock
        price, height, width, depth = row[4].to_i, row[5].to_i, row[6].to_i, row[7].to_i

        row << case
        when price < 3000 then "0"
        when price < 6000 then "1"
        when price < 9000 then "2"
        when price < 12000 then "3"
        when price < 15000 then "4"
        else "5"
        end

        row << case
        when height < 80 then "0"
        when height < 110 then "1"
        when height < 150 then "2"
        else "3"
        end

        row << case
        when width < 80 then "0"
        when width < 110 then "1"
        when width < 150 then "2"
        else "3"
        end

        row << case
        when depth < 80 then "0"
        when depth < 110 then "1"
        when depth < 150 then "2"
        else "3"
        end

        rows << "(%s, '%s', '%s', '%s', %s, %s, %s, %s, '%s', '%s', '%s', %s, %s, %s, %s, %s, %s)" % row.map!(&:to_s)

        if !row[9].nil? && row[9] != ''
          row[9].split(',').each do |feature|
            feats << "('%s', %s)" % [feature, row[0]]
          end
        end
      end

    transaction('post_api_chair') do
      sql = "INSERT INTO chair(id, name, description, thumbnail, price, height, width, depth, color, features, kind, popularity, stock, price_t, height_t, width_t, depth_t) VALUES #{rows.join(',')}"
      db.query(sql)

      sql = "INSERT INTO chair_features (name, chair_id) values #{feats.join(',')}"
      db.query(sql)
    end

    status 201
  end

  post '/api/chair/buy/:id' do
    unless body_json_params[:email]
      puts 'post buy chair failed: email not found in request body'
      halt 400
    end

    id =
      begin
        Integer(params[:id], 10)
      rescue ArgumentError => e
        puts "post buy chair failed: #{e.inspect}"
        halt 400
      end

    db.xquery('UPDATE chair SET stock = stock - 1 WHERE id = ? AND stock > 0', id)

    if db.affected_rows == 0
      halt 404
    end

    status 200
  end

  get '/api/chair/search/condition' do
    CHAIR_SEARCH_CONDITION.to_json
  end

  get '/api/estate/low_priced' do
    sql = "SELECT * FROM estate ORDER BY rent ASC, id ASC LIMIT #{LIMIT}" # XXX:
    estates = db.xquery(sql).to_a
    { estates: estates.map! { |e| camelize_keys_for_estate(e) } }.to_json
  end

  get '/api/estate/search' do
    search_queries = []
    query_params = []

    if params[:doorHeightRangeId] && params[:doorHeightRangeId].size > 0
      search_queries << 'door_height_t = ?'
      query_params << params[:doorHeightRangeId].to_i
    end

    if params[:doorWidthRangeId] && params[:doorWidthRangeId].size > 0
      search_queries << 'door_width_t = ?'
      query_params << params[:doorWidthRangeId].to_i
    end

    if params[:rentRangeId] && params[:rentRangeId].size > 0
      search_queries << 'rent_t = ?'
      query_params << params[:rentRangeId].to_i
    end

    if params[:features] && params[:features].size > 0
      features = params[:features].split(',')
      ids = db.xquery("SELECT estate_id id, COUNT(*) num FROM estate_features WHERE name IN (?) GROUP BY estate_id HAVING num = ?", features, features.size).map { |r| r[:id] }
      if ids.empty?
        search_queries << "1!=1"
      else
        search_queries << "id IN (?)"
        query_params << ids
      end
    end

    if search_queries.size == 0
      puts "Search condition not found"
      halt 400
    end

    page =
      begin
        Integer(params[:page], 10)
      rescue ArgumentError => e
        puts "Invalid format page parameter: #{e.inspect}"
        halt 400
      end

    per_page =
      begin
        Integer(params[:perPage], 10)
      rescue ArgumentError => e
        puts "Invalid format perPage parameter: #{e.inspect}"
        halt 400
      end

    sqlprefix = 'SELECT * FROM estate WHERE '
    search_condition = search_queries.join(' AND ')
    limit_offset = " ORDER BY popularity DESC, id ASC LIMIT #{per_page} OFFSET #{per_page * page}" # XXX:
    count_prefix = 'SELECT COUNT(*) as count FROM estate WHERE '

    count = db.xquery("#{count_prefix}#{search_condition}", query_params).first[:count]
    estates = db.xquery("#{sqlprefix}#{search_condition}#{limit_offset}", query_params).to_a

    { count: count, estates: estates.map! { |e| camelize_keys_for_estate(e) } }.to_json
  end

  post '/api/estate/nazotte' do
    coordinates = body_json_params[:coordinates]

    unless coordinates
      puts "post search estate nazotte failed: coordinates not found"
      halt 400
    end

    if !coordinates.is_a?(Array) || coordinates.empty?
      puts "post search estate nazotte failed: coordinates are empty"
      halt 400
    end

    longitudes = coordinates.map { |c| c[:longitude] }
    latitudes = coordinates.map { |c| c[:latitude] }
    bounding_box = {
      top_left: {
        longitude: longitudes.min,
        latitude: latitudes.min,
      },
      bottom_right: {
        longitude: longitudes.max,
        latitude: latitudes.max,
      },
    }

    coordinates_to_text = "'POLYGON((%s))'" % coordinates.map { |c| '%f %f' % c.values_at(:latitude, :longitude) }.join(',')

    sql = "SELECT * FROM estate WHERE latitude <= ? AND latitude >= ? AND longitude <= ? AND longitude >= ? AND ST_Contains(ST_PolygonFromText(#{coordinates_to_text}), POINT(latitude, longitude)) ORDER BY popularity DESC, id ASC LIMIT #{NAZOTTE_LIMIT}"

    nazotte_estates = db.xquery(sql, bounding_box[:bottom_right][:latitude], bounding_box[:top_left][:latitude], bounding_box[:bottom_right][:longitude], bounding_box[:top_left][:longitude]).to_a

    {
      estates: nazotte_estates.map! { |e| camelize_keys_for_estate(e) },
      count: nazotte_estates.size,
    }.to_json
  end

  get '/api/estate/:id' do
    id =
      begin
        Integer(params[:id], 10)
      rescue ArgumentError => e
        puts "Request parameter \"id\" parse error: #{e.inspect}"
        halt 400
      end

    estate = db.xquery('SELECT * FROM estate WHERE id = ?', id).first
    unless estate
      puts "Requested id's estate not found: #{id}"
      halt 404
    end

    camelize_keys_for_estate(estate).to_json
  end

  post '/api/estate' do
    unless params[:estates]
      puts 'Failed to get form file'
      halt 400
    end

    feats = []
    rows  = []
      CSV.parse(params[:estates][:tempfile].read, skip_blanks: true) do |row|
        #  0,    1,           2,         3,       4,        5,         6,    7,           8,          9,       10,         11
        # id, name, description, thumbnail, address, latitude, longitude, rent, door_height, door_width, features, popularity
        rent, door_height, door_width = row[7].to_i, row[8].to_i, row[9].to_i

        row << case
        when rent < 50000 then "0"
        when rent < 100000 then "1"
        when rent < 150000 then "2"
        else "3"
        end

        row << case
        when door_height < 80 then "0"
        when door_height < 110 then "1"
        when door_height < 150 then "2"
        else "3"
        end

        row << case
        when door_width < 80 then "0"
        when door_width < 110 then "1"
        when door_width < 150 then "2"
        else "3"
        end

        rows << "(%s, '%s', '%s', '%s', '%s', %s, %s, %s, %s, %s, '%s', %s, %s, %s, %s)" % row.map!(&:to_s)

        if !row[10].nil? && row[10] != ''
          row[10].split(',').each do |feature|
            feats << "('%s', %s)" % [feature, row[0]]
          end
        end
      end

    transaction('post_api_estate') do
      sql = "INSERT INTO estate(id, name, description, thumbnail, address, latitude, longitude, rent, door_height, door_width, features, popularity, rent_t, door_height_t, door_width_t) VALUES #{rows.join(',')}"
      db.query(sql)

      sql = "INSERT INTO estate_features (name, estate_id) values #{feats.join(',')}"
      db.query(sql)
    end

    status 201
  end

  post '/api/estate/req_doc/:id' do
    unless body_json_params[:email]
      puts 'post request document failed: email not found in request body'
      halt 400
    end

    id =
      begin
        Integer(params[:id], 10)
      rescue ArgumentError => e
        puts "post request document failed: #{e.inspect}"
        halt 400
      end

    estate = db.xquery('SELECT * FROM estate WHERE id = ?', id).first
    unless estate
      puts "Requested id's estate not found: #{id}"
      halt 404
    end

    status 200
  end

  ESTATE_SEARCH_CONDITION_JSON = ESTATE_SEARCH_CONDITION.to_json.freeze

  get '/api/estate/search/condition' do
    ESTATE_SEARCH_CONDITION_JSON
  end

  get '/api/recommended_estate/:id' do
    id =
      begin
        Integer(params[:id], 10)
      rescue ArgumentError => e
        puts "Request parameter \"id\" parse error: #{e.inspect}"
        halt 400
      end

    chair = db.xquery('SELECT * FROM chair WHERE id = ?', id).first
    unless chair
      puts "Requested id's chair not found: #{id}"
      halt 404
    end

    w = chair[:width]
    h = chair[:height]
    d = chair[:depth]

    sizes = [w, h, d].sort
    sql = "SELECT * FROM estate WHERE (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) ORDER BY popularity DESC, id ASC LIMIT #{LIMIT}"
    estates = db.xquery(sql, sizes[0], sizes[1], sizes[1], sizes[0]).to_a

    { estates: estates.map! { |e| camelize_keys_for_estate(e) } }.to_json
  end
end
