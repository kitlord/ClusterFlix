#!/usr/bin/env bash
# Upload ratings.csv and movies.csv from ./data into HDFS /data/raw.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose exec -T namenode bash -c '
  set -e
  hdfs dfs -mkdir -p /data/raw/ratings /data/raw/movies
  hdfs dfs -put -f /data/ratings.csv /data/raw/ratings/ratings.csv
  hdfs dfs -put -f /data/movies.csv /data/raw/movies/movies.csv
  echo "--- HDFS /data/raw ---"
  hdfs dfs -ls -R /data/raw
'
