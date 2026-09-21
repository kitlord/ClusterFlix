-- Report 3: how many ratings each star value received (0.5 .. 5.0).
-- Output: /report/rating_distribution (merged to report/rating_distribution.csv
-- by scripts/hive_report.sh).
INSERT OVERWRITE LOCAL DIRECTORY '/report/rating_distribution'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT rating AS rating,
       COUNT(*) AS num_ratings
FROM ratings
GROUP BY rating
ORDER BY rating;
