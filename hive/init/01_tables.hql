-- External tables over the raw MovieLens CSVs in HDFS.
-- Both files keep their header line, skipped via skip.header.line.count.
-- Notes:
--  - full hdfs URIs in LOCATION (the CLI session defaults to the local FS)
--  - OpenCSVSerde defaults are already comma / double-quote / backslash,
--    so WITH SERDEPROPERTIES is omitted on purpose (a bare double-quote
--    inside the properties confuses the CLI statement splitter)
--  - no semicolons inside comments - the CLI splits statements on them

CREATE EXTERNAL TABLE IF NOT EXISTS ratings (
  userId  INT,
  movieId INT,
  rating  DOUBLE,
  ts      BIGINT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/data/raw/ratings'
TBLPROPERTIES ('skip.header.line.count'='1');

-- movie titles can contain commas, so parse as quoted CSV. OpenCSVSerde
-- returns every column as STRING, cast where needed in the report queries.
CREATE EXTERNAL TABLE IF NOT EXISTS movies (
  movieId STRING,
  title   STRING,
  genres  STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
STORED AS TEXTFILE
LOCATION 'hdfs://namenode:9000/data/raw/movies'
TBLPROPERTIES ('skip.header.line.count'='1');
