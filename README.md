# 🎬 CineMatch

A minimal MovieLens movie recommender built for a big-data course.
Everything runs on a single laptop with **Docker Compose** - the host only needs
**Docker** and **Make**.

```
MovieLens ──> HDFS ──> Spark/Scala/MLlib (ALS) ──> MongoDB <── Flask UI
                          │                                          ↑
                          └──> Parquet (movie stats in HDFS)         │
                                     └──> Hive ──> ./report/*.csv ───┘
```

| Stage      | Technology |
|------------|------------|
| Storage    | HDFS 3.3.6 (1 NameNode + 1 DataNode) |
| Processing | Apache Spark 3.5.1 standalone (Scala 2.12), MLlib ALS |
| Serving    | MongoDB 7 (recommendations), HDFS Parquet (movie stats) |
| Analytics  | Hive 3.1.3 (external tables over the CSVs in HDFS) |
| Web UI     | Python 3.12 / Flask (user dropdown + recommendations + reports) |

Dataset: [MovieLens ml-latest-small](https://grouplens.org/datasets/movielens/latest/)
(~100k ratings, ~9.7k movies, 610 users) - downloaded automatically by
`make setup`, never committed.

The ALS model (rank 10, 10 iterations, regParam 0.1, 80/20 split) reaches a
test **RMSE ≈ 0.88** on this dataset.

## Quick start

```bash
make all      # setup + train + report + serve
```

Then open <http://localhost:5000> - pick a user and see their top-10
recommended movies; <http://localhost:5000/reports> shows the Hive reports.

`make all` runs, in order:

1. **setup** - download MovieLens, build images, start HDFS/Spark/Mongo, load
   the CSVs into HDFS (`/data/raw/...`)
2. **train** - compile the Scala job with sbt (in a container), submit it to
   Spark: trains ALS, prints test RMSE, writes top-10 recommendations per user
   to MongoDB (`cinematch.recommendations`) and per-movie stats as Parquet to
   HDFS (`/data/processed/movie_stats`)
3. **report** - create Hive external tables over the raw CSVs and export three
   reports to `./report/` (most-rated movies, average rating by genre, rating
   distribution)
4. **serve** - start the Flask app

## Makefile targets

| Command       | What it does |
|---------------|--------------|
| `make setup`  | Download dataset, build images, start infrastructure, load HDFS |
| `make train`  | Build the Scala job, train ALS, write MongoDB + Parquet |
| `make report` | Create Hive tables, export the 3 reports to `./report/` |
| `make serve`  | Start the Flask web app on :5000 |
| `make check`  | Verify HDFS data, RMSE, MongoDB docs, report files, HTTP 200 |
| `make all`    | setup + train + report + serve |
| `make down`   | Stop all containers (data volumes are kept) |
| `make logs`   | Tail all container logs |
| `make clean`  | Stop everything and delete containers, volumes, dataset, reports |

## Project layout

```
docker-compose.yml        all 7 services (HDFS x2, Spark x2, Mongo, Hive, web)
hadoop / spark / mongo
spark/
  Dockerfile              sbt builder image (compiles the job in a container)
  build.sbt               Scala 2.12, Spark 3.5.1 + mongo-spark-connector
  src/main/scala/cinematch/Recommender.scala   the training job
hive/
  init/01_tables.hql      external tables over the CSVs in HDFS
  reports/*.hql           the three analytical reports
web/
  Dockerfile, app.py, templates/    Flask UI
scripts/                  setup / load / build / train / report / check
Makefile
```

## Ports

| Port | Service |
|------|---------|
| 5000 | Flask web app |
| 9870 | HDFS NameNode web UI |
| 8080 | Spark master web UI |

MongoDB is only reachable inside the Compose network (`mongo:27017`).

## Requirements

- Docker (with Compose v2) and Make - nothing else
- ~8 GB of free RAM for the stack and ~10 GB of disk for images/volumes
- Internet access on first run (dataset + Docker images + Maven/sbt deps)

## How recommendations are produced

`spark/src/main/scala/cinematch/Recommender.scala`:

1. reads `ratings.csv` from HDFS, splits 80/20 (`seed = 42`)
2. trains `ALS` (MLlib), evaluates test **RMSE** and stores it in
   HDFS `/output/rmse` (also copied to `./report/rmse.txt`)
3. `recommendForAllUsers(10)`, joined with titles/genres, written to
   MongoDB as one document per user:
   `{ userId, recommendations: [{ movieId, title, genres, predictedRating }] }`
4. per-movie `numRatings` / `avgRating` stats written as Parquet to
   `/data/processed/movie_stats`

Hive reads the *same* raw CSVs through external tables (header line skipped,
`OpenCSVSerde` for the quoted titles) and exports the reports with
`INSERT OVERWRITE LOCAL DIRECTORY`, merged into `./report/*.csv` by
`scripts/hive_report.sh`.

## Troubleshooting

- **Port already allocated** - free ports 5000 / 8080 / 9870 or edit the
  `ports:` section of `docker-compose.yml`.
- **`make train` recompiles from zero** - the sbt cache lives in Docker
  volumes (`sbt_cache`, `ivy_cache`, `coursier_cache`); `make clean` removes
  them, `make down` keeps them.
- **Web shows "No recommendations yet"** - run `make train` first.
- **HDFS won't leave safemode** - check `docker compose logs datanode`; the
  DataNode must register within a few minutes of the NameNode starting.
