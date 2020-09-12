DROP DATABASE IF EXISTS isuumo;
CREATE DATABASE isuumo;

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
    INDEX idx_rent_t (rent_t),
    INDEX idx_door_height_t (door_height_t),
    INDEX idx_door_width_t (door_width_t),

    INDEX idx_name (name),
    INDEX idx_address (address),
    INDEX idx_rent (rent),
    INDEX idx_id_rent (id, rent),
    INDEX idx_door_height_door_width (door_height, door_width),
    INDEX idx_door_width_door_height (door_width, door_height),
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
    INDEX idx_price_t (price_t),
    INDEX idx_height_t (height_t),
    INDEX idx_width_t (width_t),
    INDEX idx_depth_t (depth_t),

    INDEX idx_name (name),
    INDEX idx_price (price),
    INDEX idx_depth (depth),
    INDEX idx_color (color),
    INDEX idx_kind (kind),
    INDEX idx_popularity (popularity),
    INDEX idx_stock_price (stock, price),
    INDEX idx_height_width (height, width),
    INDEX idx_width_height (width, height)
);

CREATE TABLE isuumo.estate_features
(
    name        VARCHAR(64)         NOT NULL,
    estate_id   INTEGER             NOT NULL,
    PRIMARY KEY (name, estate_id)
);

CREATE TABLE isuumo.chair_features
(
    name        VARCHAR(64)         NOT NULL,
    chair_id    INTEGER             NOT NULL,
    PRIMARY KEY (name, chair_id)
);
