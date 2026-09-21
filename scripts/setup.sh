#!/usr/bin/env bash
# Download the MovieLens dataset, start the infrastructure and load data into HDFS.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p data report

if [ -f data/ratings.csv ] && [ -f data/movies.csv ]; then
  echo ">> Dataset already present in ./data, skipping download"
else
  echo ">> Downloading MovieLens ml-latest-small (~1 MB)..."
  curl -L --fail --retry 3 -o /tmp/ml-latest-small.zip \
    https://files.grouplens.org/datasets/movielens/ml-latest-small.zip
  unzip -o -q /tmp/ml-latest-small.zip -d /tmp/ml-extract
  mv /tmp/ml-extract/ml-latest-small/ratings.csv data/ratings.csv
  mv /tmp/ml-extract/ml-latest-small/movies.csv data/movies.csv
  rm -rf /tmp/ml-extract /tmp/ml-latest-small.zip
  echo ">> Dataset extracted to ./data"
fi

echo ">> Building images (scala-build, web)..."
docker compose build scala-build web

echo ">> Starting HDFS, Spark, MongoDB..."
docker compose up -d namenode datanode mongo spark-master spark-worker

bash scripts/wait_hdfs.sh
bash scripts/load_hdfs.sh

echo ">> Setup complete."
