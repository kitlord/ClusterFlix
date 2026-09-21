COMPOSE := docker compose

.DEFAULT_GOAL := help
.PHONY: setup train report serve check all down logs clean help

## setup: Download MovieLens, build images, start infrastructure, load HDFS
setup:
	bash scripts/setup.sh

## train: Build the Scala job, train ALS with Spark/MLlib, write MongoDB + Parquet
train:
	bash scripts/build.sh
	bash scripts/train.sh

## report: Create Hive external tables and export the 3 reports to ./report
report:
	bash scripts/hive_report.sh

## serve: Start the Flask web app on http://localhost:5000
serve:
	bash scripts/serve.sh

## check: Verify HDFS data, RMSE, MongoDB recommendations, Hive reports, Flask
check:
	bash scripts/check.sh

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
	rm -rf data report spark/target

help:
	@echo "CineMatch - MovieLens recommender (HDFS / Spark / Hive / MongoDB / Flask)"
	@echo
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  make /'
