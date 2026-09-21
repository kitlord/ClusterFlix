#!/usr/bin/env bash
# Download the MongoDB Spark connector and its driver jars into spark/lib/
# so that `spark-submit --jars` needs no network at training time.
# (--packages would resolve a version RANGE from Maven Central on every run
# and fails on any DNS/proxy hiccup inside the container.)
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=https://repo1.maven.org/maven2
mkdir -p spark/lib

jars=(
  "org/mongodb/spark/mongo-spark-connector_2.12/10.4.0/mongo-spark-connector_2.12-10.4.0.jar"
  "org/mongodb/mongodb-driver-sync/5.1.1/mongodb-driver-sync-5.1.1.jar"
  "org/mongodb/mongodb-driver-core/5.1.1/mongodb-driver-core-5.1.1.jar"
  "org/mongodb/bson/5.1.1/bson-5.1.1.jar"
  "org/mongodb/bson-record-codec/5.1.1/bson-record-codec-5.1.1.jar"
)

for path in "${jars[@]}"; do
  file="spark/lib/$(basename "$path")"
  if [ -s "$file" ]; then
    echo ">> $file already present"
  else
    echo ">> downloading $(basename "$path") ..."
    curl -fL --retry 3 --silent --show-error -o "$file" "$BASE/$path"
  fi
done

echo ">> MongoDB connector jars ready in spark/lib/"
