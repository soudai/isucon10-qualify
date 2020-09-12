UPDATE isuumo.estate
SET rent_t = CASE WHEN rent < 50000 THEN 0 WHEN rent < 100000 THEN 1 WHEN rent < 150000 THEN 2 ELSE 3 END,
    door_height_t = CASE WHEN door_height < 80 THEN 0 WHEN door_height < 110 THEN 1 WHEN door_height < 150 THEN 2 ELSE 3 END,
    door_width_t = CASE WHEN door_width < 80 THEN 0 WHEN door_width < 110 THEN 1 WHEN door_width < 150 THEN 2 ELSE 3 END;

UPDATE isuumo.chair
SET price_t = CASE WHEN price < 3000 THEN 0 WHEN price < 6000 THEN 1 WHEN price < 9000 THEN 2
                   WHEN price < 12000 THEN 3 WHEN price < 15000 THEN 4 ELSE 5 END,
    height_t = CASE WHEN height < 80 THEN 0 WHEN height < 110 THEN 1 WHEN height < 150 THEN 2 ELSE 3 END,
    width_t = CASE WHEN width < 80 THEN 0 WHEN width < 110 THEN 1 WHEN width < 150 THEN 2 ELSE 3 END,
    depth_t = CASE WHEN depth < 80 THEN 0 WHEN depth < 110 THEN 1 WHEN depth < 150 THEN 2 ELSE 3 END;
