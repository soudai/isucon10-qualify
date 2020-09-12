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
    INDEX idx_name (name),
    INDEX idx_thumbnail (thumbnail),
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
    INDEX idx_name (name),
    INDEX idx_thumbnail (thumbnail),
    INDEX idx_price (price),
    INDEX idx_depth (depth),
    INDEX idx_color (color),
    INDEX idx_features (features),
    INDEX idx_kind (kind),
    INDEX idx_popularity (popularity),
    INDEX idx_stock (stock),
    INDEX idx_stock_price (price, stock),
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
