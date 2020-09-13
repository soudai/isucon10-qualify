DROP DATABASE IF EXISTS isuumo;
CREATE DATABASE isuumo COLLATE utf8mb4_general_ci;

DROP TABLE IF EXISTS isuumo.estate;
DROP TABLE IF EXISTS isuumo.chair;
DROP TABLE IF EXISTS isuumo.estate_features;
DROP TABLE IF EXISTS isuumo.chair_features;

CREATE TABLE isuumo.estate
(
    id          INTEGER             NOT NULL PRIMARY KEY,
    name        VARCHAR(64)         NOT NULL,
    description VARCHAR(4096)       NOT NULL,
    thumbnail   VARCHAR(128)        NOT NULL,
    address     VARCHAR(128)        NOT NULL,
    latitude    DOUBLE PRECISION    NOT NULL,
    longitude   DOUBLE PRECISION    NOT NULL,
    rent        INTEGER             NOT NULL,
    door_height INTEGER             NOT NULL,
    door_width  INTEGER             NOT NULL,
    features    VARCHAR(64)         NOT NULL,
    popularity  INTEGER             NOT NULL,

    rent_t        INTEGER,
    door_height_t INTEGER,
    door_width_t  INTEGER,

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L357-L370
    -- 複数index効かせられないMySQLでは種類ごとの同値(=)検索で引っ掛けるのがORDER BYも効かせられる余地があってよい
    -- ORDER BY popularity DESC, id ASC LIMIT #{per_page} OFFSET #{per_page * page} があるので
    -- INDEX idx_rent_t (rent_t, popularity DESC) にしてORDER BY LIMIT optimizationも狙うべきだった(MySQL 8限定)
    INDEX idx_rent_t (rent_t),
    INDEX idx_door_height_t (door_height_t),
    INDEX idx_door_width_t (door_width_t),

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L348
    -- SELECT * FROM estate ORDER BY rent ASC, id ASC LIMIT #{LIMIT}
    -- rentのORDER BY LIMIT optimization狙い
    INDEX idx_rent (rent),

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L442
    -- SELECT * FROM estate WHERE latitude <= ? AND latitude >= ? AND longitude <= ? AND longitude >= ? ORDER BY popularity DESC, id ASC
    -- MySQではこのクエリにこのindexを効率よく効かせるのはむずかしい
    -- geometry (point)型のカラム足してspatial index試したかったね
    -- memo: https://qiita.com/qyen/items/bc4a7be812253c2be9f9
    INDEX idx_latitude_longitude (latitude, longitude),
    INDEX idx_longitude_latitude (longitude, latitude)
);

CREATE TABLE isuumo.chair
(
    id          INTEGER         NOT NULL PRIMARY KEY,
    name        VARCHAR(64)     NOT NULL,
    description VARCHAR(4096)   NOT NULL,
    thumbnail   VARCHAR(128)    NOT NULL,
    price       INTEGER         NOT NULL,
    height      INTEGER         NOT NULL,
    width       INTEGER         NOT NULL,
    depth       INTEGER         NOT NULL,
    color       VARCHAR(64)     NOT NULL,
    features    VARCHAR(64)     NOT NULL,
    kind        VARCHAR(64)     NOT NULL,
    popularity  INTEGER         NOT NULL,
    stock       INTEGER         NOT NULL,

    price_t     INTEGER,
    height_t    INTEGER,
    width_t     INTEGER,
    depth_t     INTEGER,

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L155-L173
    -- 複数index効かせられないMySQLでは種類ごとの同値(=)検索で引っ掛けるのがORDER BYも効かせられる余地があってよい
    -- ORDER BY popularity DESC, id ASC LIMIT #{per_page} OFFSET #{per_page * page} があるので
    -- INDEX idx_price_t (price_t, popularity DESC) にしてORDER BY LIMIT optimizationも狙うべきだった(MySQL 8限定)
    INDEX idx_price_t (price_t),
    INDEX idx_height_t (height_t),
    INDEX idx_width_t (width_t),
    INDEX idx_depth_t (depth_t),

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L146
    -- SELECT * FROM chair WHERE stock > 0 ORDER BY price ASC, id ASC LIMIT #{LIMIT}
    -- ほとんど stock > 0 のはず, priceのORDER BY LIMIT optimization狙い
    INDEX idx_price (price),

    -- 不要
    INDEX idx_depth (depth),

    -- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L175-L183
    INDEX idx_color (color),
    INDEX idx_kind (kind),

    -- 常に他の検索条件との複合で必要なので単体では不要
    INDEX idx_popularity (popularity),

    -- 不要
    INDEX idx_stock_price (stock, price),
    INDEX idx_height_width (height, width),
    INDEX idx_width_height (width, height)
);

-- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L372-L381
CREATE TABLE isuumo.estate_features
(
    name        VARCHAR(64)         NOT NULL,
    estate_id   INTEGER             NOT NULL,
    PRIMARY KEY (name, estate_id)
);

-- https://github.com/soudai/isucon10-qualify/blob/1be06d2540eb94244596e9a7b541f7c4caf4c14f/webapp/ruby/app.rb#L185-L194
CREATE TABLE isuumo.chair_features
(
    name        VARCHAR(64)         NOT NULL,
    chair_id    INTEGER             NOT NULL,
    PRIMARY KEY (name, chair_id)
);
