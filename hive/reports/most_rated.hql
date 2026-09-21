-- Report 1: the 20 most-rated movies.
-- Output: /report/most_rated (merged to report/most_rated.csv by scripts/hive_report.sh).
-- Titles may contain commas, so wrap them in CSV quotes. The quote character is
-- produced with chr(34) because a literal double-quote character anywhere in a
-- CLI script (comments included) breaks the statement splitter.
INSERT OVERWRITE LOCAL DIRECTORY '/report/most_rated'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT CONCAT(chr(34), REGEXP_REPLACE(m.title, chr(34), CONCAT(chr(34), chr(34))), chr(34)) AS title,
       COUNT(*) AS num_ratings
FROM ratings r
JOIN movies m ON r.movieId = m.movieId
GROUP BY m.title
ORDER BY num_ratings DESC
LIMIT 20;
