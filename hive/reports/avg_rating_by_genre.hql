-- Report 2: average rating per genre. A movie can have several genres and is
-- counted once per genre (explode of the pipe-separated list, done in a
-- subquery because LATERAL VIEW cannot follow a JOIN clause).
-- Output: /report/avg_rating_by_genre (merged to report/avg_rating_by_genre.csv
-- by scripts/hive_report.sh).
INSERT OVERWRITE LOCAL DIRECTORY '/report/avg_rating_by_genre'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT mg.genre AS genre,
       ROUND(AVG(r.rating), 4) AS avg_rating,
       COUNT(*) AS num_ratings
FROM ratings r
JOIN (
  SELECT movieId, genre
  FROM movies
  LATERAL VIEW explode(split(genres, '\\|')) g AS genre
) mg ON r.movieId = mg.movieId
GROUP BY mg.genre
ORDER BY avg_rating DESC;
