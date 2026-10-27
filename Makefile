COMPOSE := docker compose

.DEFAULT_GOAL := help
.PHONY: setup train report serve all down logs clean help

## setup: Download MovieLens, build images, start infrastructure, load HDFS
setup:
	mkdir -p data report
	[ -f data/ratings.csv ] || { curl -fL --retry 3 -o /tmp/ml-latest-small.zip https://files.grouplens.org/datasets/movielens/ml-latest-small.zip && unzip -o -q /tmp/ml-latest-small.zip -d /tmp/ml-extract && mv /tmp/ml-extract/ml-latest-small/ratings.csv /tmp/ml-extract/ml-latest-small/movies.csv data/ && rm -rf /tmp/ml-extract /tmp/ml-latest-small.zip; }
	$(COMPOSE) build scala-build web
	$(COMPOSE) up -d namenode datanode mongo spark-master spark-worker
	bash scripts/wait_hdfs.sh
	$(COMPOSE) exec -T namenode hdfs dfs -mkdir -p /data/raw/ratings /data/raw/movies
	$(COMPOSE) exec -T namenode hdfs dfs -put -f /data/ratings.csv /data/raw/ratings/ratings.csv
	$(COMPOSE) exec -T namenode hdfs dfs -put -f /data/movies.csv /data/raw/movies/movies.csv

## train: Build the Scala job, train ALS with Spark/MLlib, write MongoDB + Parquet
train:
	$(COMPOSE) run --rm scala-build
	bash scripts/train.sh

## report: Create Hive external tables and export the 3 reports to ./report
report:
	bash scripts/hive_report.sh

## serve: Start the Flask web app on http://localhost:5000
serve:
	$(COMPOSE) up -d web

## all: setup + train + report + serve (the full pipeline)
all: setup train report serve

## down: Stop and remove all containers (data volumes are kept)
down:
	$(COMPOSE) down

## logs: Tail logs from all containers
logs:
	$(COMPOSE) logs -f --tail=50

## clean: Stop everything and delete containers, volumes, dataset, reports, build output
clean:
	$(COMPOSE) down -v --remove-orphans
	rm -rf data report spark/target spark/lib

help:
	@echo "CineMatch - MovieLens recommender (HDFS / Spark / Hive / MongoDB / Flask)"
	@echo
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  make /'
