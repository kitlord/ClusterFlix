#!/usr/bin/env bash
# Run the Spark job: ALS training, RMSE, recommendations -> MongoDB, stats -> HDFS Parquet.
set -euo pipefail
cd "$(dirname "$0")/.."

JAR=spark/target/scala-2.12/cinematch_2.12-1.0.0.jar
if [ ! -f "$JAR" ]; then
  echo "!! $JAR not found - run 'make train' (which builds first) or 'bash scripts/build.sh'" >&2
  exit 1
fi

echo ">> Fetching MongoDB connector jars (cached in spark/lib/)..."
bash scripts/fetch_mongo_jars.sh

echo ">> Waiting for MongoDB..."
for i in $(seq 1 30); do
  if docker compose exec -T mongo mongosh --quiet --eval 'db.adminCommand({ping: 1})' >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "!! MongoDB not reachable - check 'docker compose logs mongo'" >&2
    exit 1
  fi
  sleep 2
done

echo ">> Submitting Spark job to spark://spark-master:7077 ..."
docker compose exec -T spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --class cinematch.Recommender \
  --conf spark.executor.memory=1g \
  --conf spark.driver.memory=1g \
  --conf spark.sql.shuffle.partitions=8 \
  --conf spark.mongodb.write.connection.uri=mongodb://mongo:27017/cinematch \
  --jars /spark/lib/mongo-spark-connector_2.12-10.4.0.jar,/spark/lib/mongodb-driver-sync-5.1.1.jar,/spark/lib/mongodb-driver-core-5.1.1.jar,/spark/lib/bson-5.1.1.jar,/spark/lib/bson-record-codec-5.1.1.jar \
  /spark/target/scala-2.12/cinematch_2.12-1.0.0.jar

echo ">> Copying RMSE from HDFS to ./report/rmse.txt"
docker compose exec -T namenode hdfs dfs -cat "/output/rmse/part-*" > report/rmse.txt
cat report/rmse.txt
echo ">> Training complete."
