# frozen_string_literal: true

require 'sinatra'
require 'mysql2'
require 'mysql2-cs-bind'
require 'csv'

require 'newrelic_rpm'
require 'new_relic/agent/method_tracer'
require 'new_relic/agent/tracer'


class Mysql2ClientWithNewRelic < Mysql2::Client
  def initialize(*args)
    super
  end

  def query(sql, *args)
    callback = -> (result, metrics, elapsed) do
      NewRelic::Agent::Datastores.notice_sql(sql, metrics, elapsed)
    end
    op = sql[/^(select|insert|update|delete|begin|commit|rollback)/i] || 'other'
    table = sql[/\bchair|estate\b/] || 'other'
    NewRelic::Agent::Datastores.wrap('MySQL', op, table, callback) do
      super
    end
  end
end


class App < Sinatra::Base
  LIMIT = 20
  NAZOTTE_LIMIT = 50
  CHAIR_SEARCH_CONDITION = JSON.parse(File.read('../fixture/chair_condition.json'), symbolize_names: true)
  ESTATE_SEARCH_CONDITION = JSON.parse(File.read('../fixture/estate_condition.json'), symbolize_names: true)

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader
  end

  configure do
    # enable :logging
  end

  before do
    [
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
    ].each do |regexp|
      if regexp.match(request.user_agent)
        puts "BOT!!!!!!!!111: #{request.user_agent}"
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
      #Thread.current[:db] ||= Mysql2::Client.new(
      return Thread.current[:db] if Thread.current[:db]

      params = {
        host: db_info[:host],
        port: db_info[:port],
        username: db_info[:username],
        password: db_info[:password],
        database: db_info[:database],
        reconnect: true,
        symbolize_keys: true,
      }

      Thread.current[:db] = ENV['NEW_RELIC_AGENT_ENABLED'] ? Mysql2ClientWithNewRelic.new(params) : Mysql2::Client.new(params)
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

      # chair_price = CHAIR_SEARCH_CONDITION[:price][:ranges][params[:priceRangeId].to_i]
      # unless chair_price
      #   puts "priceRangeID invalid: #{params[:priceRangeId]}"
      #   halt 400
      # end

      # if chair_price[:min] != -1
      #   search_queries << 'price >= ?'
      #   query_params << chair_price[:min]
      # end

      # if chair_price[:max] != -1
      #   search_queries << 'price < ?'
      #   query_params << chair_price[:max]
      # end
    end

    if params[:heightRangeId] && params[:heightRangeId].size > 0
      search_queries << 'height_t = ?'
      query_params << params[:heightRangeId].to_i

      # chair_height = CHAIR_SEARCH_CONDITION[:height][:ranges][params[:heightRangeId].to_i]
      # unless chair_height
      #   puts "heightRangeId invalid: #{params[:heightRangeId]}"
      #   halt 400
      # end

      # if chair_height[:min] != -1
      #   search_queries << 'height >= ?'
      #   query_params << chair_height[:min]
      # end

      # if chair_height[:max] != -1
      #   search_queries << 'height < ?'
      #   query_params << chair_height[:max]
      # end
    end

    if params[:widthRangeId] && params[:widthRangeId].size > 0
      search_queries << 'width_t = ?'
      query_params << params[:widthRangeId].to_i

      # chair_width = CHAIR_SEARCH_CONDITION[:width][:ranges][params[:widthRangeId].to_i]
      # unless chair_width
      #   puts "widthRangeId invalid: #{params[:widthRangeId]}"
      #   halt 400
      # end

      # if chair_width[:min] != -1
      #   search_queries << 'width >= ?'
      #   query_params << chair_width[:min]
      # end

      # if chair_width[:max] != -1
      #   search_queries << 'width < ?'
      #   query_params << chair_width[:max]
      # end
    end

    if params[:depthRangeId] && params[:depthRangeId].size > 0
      search_queries << 'depth_t = ?'
      query_params << params[:depthRangeId].to_i
      # chair_depth = CHAIR_SEARCH_CONDITION[:depth][:ranges][params[:depthRangeId].to_i]
      # unless chair_depth
      #   puts "depthRangeId invalid: #{params[:depthRangeId]}"
      #   halt 400
      # end

      # if chair_depth[:min] != -1
      #   search_queries << 'depth >= ?'
      #   query_params << chair_depth[:min]
      # end

      # if chair_depth[:max] != -1
      #   search_queries << 'depth < ?'
      #   query_params << chair_depth[:max]
      # end
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

#       params[:features].split(',').each do |feature_condition|
#         search_queries << "features LIKE CONCAT('%', ?, '%')"
#         query_params.push(feature_condition)
#       end
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

    transaction('post_api_chair') do
      CSV.parse(params[:chairs][:tempfile].read, skip_blanks: true) do |row|
        sql = 'INSERT INTO chair(id, name, description, thumbnail, price, height, width, depth, color, features, kind, popularity, stock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        db.xquery(sql, *row.map(&:to_s))
        db.xquery(<<-SQL, row[0])
UPDATE chair
SET price_t = CASE WHEN price < 3000 THEN 0 WHEN price < 6000 THEN 1 WHEN price < 9000 THEN 2
                   WHEN price < 12000 THEN 3 WHEN price < 15000 THEN 4 ELSE 5 END,
    height_t = CASE WHEN height < 80 THEN 0 WHEN height < 110 THEN 1 WHEN height < 150 THEN 2 ELSE 3 END,
    width_t = CASE WHEN width < 80 THEN 0 WHEN width < 110 THEN 1 WHEN width < 150 THEN 2 ELSE 3 END,
    depth_t = CASE WHEN depth < 80 THEN 0 WHEN depth < 110 THEN 1 WHEN depth < 150 THEN 2 ELSE 3 END
WHERE id = ?
SQL
        if !row[9].nil? && row[9] != ''
          row[9].split(',').each do |feature|
            sql = 'INSERT INTO chair_features (name, chair_id) values (?, ?)'
            db.xquery(sql, feature, row[0])
          end
        end
      end
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

    transaction('post_api_chair_buy') do |tx_name|
      chair = db.xquery('SELECT * FROM chair WHERE id = ? AND stock > 0 FOR UPDATE', id).first
      unless chair
        rollback_transaction(tx_name) if in_transaction?(tx_name)
        halt 404
      end
      db.xquery('UPDATE chair SET stock = stock - 1 WHERE id = ?', id)
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

      # door_height = ESTATE_SEARCH_CONDITION[:doorHeight][:ranges][params[:doorHeightRangeId].to_i]
      # unless door_height
      #   puts "doorHeightRangeId invalid: #{params[:doorHeightRangeId]}"
      #   halt 400
      # end

      # if door_height[:min] != -1
      #   search_queries << 'door_height >= ?'
      #   query_params << door_height[:min]
      # end

      # if door_height[:max] != -1
      #   search_queries << 'door_height < ?'
      #   query_params << door_height[:max]
      # end
    end

    if params[:doorWidthRangeId] && params[:doorWidthRangeId].size > 0
      search_queries << 'door_width_t = ?'
      query_params << params[:doorWidthRangeId].to_i

      # door_width = ESTATE_SEARCH_CONDITION[:doorWidth][:ranges][params[:doorWidthRangeId].to_i]
      # unless door_width
      #   puts "doorWidthRangeId invalid: #{params[:doorWidthRangeId]}"
      #   halt 400
      # end

      # if door_width[:min] != -1
      #   search_queries << 'door_width >= ?'
      #   query_params << door_width[:min]
      # end

      # if door_width[:max] != -1
      #   search_queries << 'door_width < ?'
      #   query_params << door_width[:max]
      # end
    end

    if params[:rentRangeId] && params[:rentRangeId].size > 0
      search_queries << 'rent_t = ?'
      query_params << params[:rentRangeId].to_i

      # rent = ESTATE_SEARCH_CONDITION[:rent][:ranges][params[:rentRangeId].to_i]
      # unless rent
      #   puts "rentRangeId invalid: #{params[:rentRangeId]}"
      #   halt 400
      # end

      # if rent[:min] != -1
      #   search_queries << 'rent >= ?'
      #   query_params << rent[:min]
      # end

      # if rent[:max] != -1
      #   search_queries << 'rent < ?'
      #   query_params << rent[:max]
      # end
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

#       params[:features].split(',').each do |feature_condition|
#         search_queries << "features LIKE CONCAT('%', ?, '%')"
#         query_params.push(feature_condition)
#       end
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

    puts "/api/estate/search: #{page} page, #{search_condition}, #{query_params.inspect}"

    { count: count, estates: estates.map! { |e| camelize_keys_for_estate(e) } }.to_json
  end

  post '/api/estate/nazotte' do
    #starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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

    sql = 'SELECT * FROM estate WHERE latitude <= ? AND latitude >= ? AND longitude <= ? AND longitude >= ? ORDER BY popularity DESC, id ASC'
    estates = db.xquery(sql, bounding_box[:bottom_right][:latitude], bounding_box[:top_left][:latitude], bounding_box[:bottom_right][:longitude], bounding_box[:top_left][:longitude]).to_a

    #puts "nazotte: #{estates.size} estates"

    estates_in_polygon = []
    estates.each do |estate|
      point = "'POINT(%f %f)'" % estate.values_at(:latitude, :longitude)
      coordinates_to_text = "'POLYGON((%s))'" % coordinates.map { |c| '%f %f' % c.values_at(:latitude, :longitude) }.join(',')
      sql = 'SELECT * FROM estate WHERE id = ? AND ST_Contains(ST_PolygonFromText(%s), ST_GeomFromText(%s))' % [coordinates_to_text, point]
      e = db.xquery(sql, estate[:id]).first
      if e
        estates_in_polygon << e
        break if estates_in_polygon.size > NAZOTTE_LIMIT
      end
    end

    #ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    #elapsed = ending - starting

    #puts "nazotte: #{elapsed} seconds"

    nazotte_estates = estates_in_polygon.take(NAZOTTE_LIMIT)
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

    transaction('post_api_estate') do
      CSV.parse(params[:estates][:tempfile].read, skip_blanks: true) do |row|
        sql = 'INSERT INTO estate(id, name, description, thumbnail, address, latitude, longitude, rent, door_height, door_width, features, popularity) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        db.xquery(sql, *row.map(&:to_s))
        db.xquery(<<-SQL, row[0])
UPDATE estate
SET rent_t = CASE WHEN rent < 50000 THEN 0 WHEN rent < 100000 THEN 1 WHEN rent < 150000 THEN 2 ELSE 3 END,
    door_height_t = CASE WHEN door_height < 80 THEN 0 WHEN door_height < 110 THEN 1 WHEN door_height < 150 THEN 2 ELSE 3 END,
    door_width_t = CASE WHEN door_width < 80 THEN 0 WHEN door_width < 110 THEN 1 WHEN door_width < 150 THEN 2 ELSE 3 END 
WHERE id = ?
SQL
        if !row[10].nil? && row[10] != ''
          row[10].split(',').each do |feature|
            sql = 'INSERT INTO estate_features (name, estate_id) values (?, ?)'
            db.xquery(sql, feature, row[0])
          end
        end
      end
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

    sql = "SELECT * FROM estate WHERE (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) OR (door_width >= ? AND door_height >= ?) ORDER BY popularity DESC, id ASC LIMIT #{LIMIT}" # XXX:    
    estates = db.xquery(sql, w, h, w, d, h, w, h, d, d, w, d, h).to_a

    { estates: estates.map! { |e| camelize_keys_for_estate(e) } }.to_json
  end
end
