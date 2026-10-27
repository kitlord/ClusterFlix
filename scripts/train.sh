#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f spark/target/scala-2.12/cinematch_2.12-1.0.0.jar ] || { echo "!! jar missing - run 'make train'" >&2; exit 1; }

mkdir -p spark/lib
BASE=https://repo1.maven.org/maven2
JARS="org/mongodb/spark/mongo-spark-connector_2.12/10.4.0/mongo-spark-connector_2.12-10.4.0.jar \
org/mongodb/mongodb-driver-sync/5.1.1/mongodb-driver-sync-5.1.1.jar \
org/mongodb/mongodb-driver-core/5.1.1/mongodb-driver-core-5.1.1.jar \
org/mongodb/bson/5.1.1/bson-5.1.1.jar \
org/mongodb/bson-record-codec/5.1.1/bson-record-codec-5.1.1.jar"
for path in $JARS; do
  f="spark/lib/$(basename "$path")"
  [ -s "$f" ] || curl -fL --retry 3 --silent --show-error -o "$f" "$BASE/$path"
done

for _ in $(seq 1 30); do
  docker compose exec -T mongo mongosh --quiet --eval 'db.adminCommand({ping: 1})' >/dev/null 2>&1 && break
  sleep 2
done

docker compose exec -T spark-master bash /spark/spark-job.sh

docker compose exec -T namenode hdfs dfs -cat "/output/rmse/part-*" > report/rmse.txt
cat report/rmse.txt
echo ">> Training complete."
