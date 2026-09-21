#!/usr/bin/env bash
# Initialize the Hive metastore, create external tables and export the 3 reports.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p report

# The apache/hive image defaults to the Tez engine (no Tez jars in the CLI),
# so queries run on MapReduce in local mode. Table locations are full hdfs://
# URIs, so the session's default filesystem stays on the local FS - that is
# what makes INSERT OVERWRITE LOCAL DIRECTORY write to /report.
# HADOOP_CLIENT_OPTS raises the CLI JVM heap: the default ~256m OOMs in the
# ORDER BY stage even on this small dataset.
HIVE_ARGS="--hiveconf hive.execution.engine=mr --hiveconf hive.exec.mode.local.auto=true"
HIVE_ENV="HADOOP_CLIENT_OPTS=-Xmx1536m"

echo ">> Starting Hive container..."
docker compose up -d hive
bash scripts/wait_hdfs.sh

echo ">> Initializing Derby metastore (first run only)..."
docker compose exec -T hive bash -c '
  if [ ! -f /data/hive/metastore_db/service.properties ]; then
    schematool -dbType derby -initSchema --verbose > /tmp/schematool.log 2>&1 \
      || { echo "!! schematool failed:"; tail -30 /tmp/schematool.log; exit 1; }
    echo "  metastore schema initialized"
  else
    echo "  metastore already initialized"
  fi
'

echo ">> Creating external tables..."
docker compose exec -T hive bash -c "cd /data/hive && $HIVE_ENV hive $HIVE_ARGS -f /hive/init/01_tables.hql" 2>/tmp/hive-tables.log
tail -1 /tmp/hive-tables.log || true

for report in most_rated avg_rating_by_genre rating_distribution; do
  echo ">> Running Hive report: $report"
  rm -f "report/${report}.csv"
  docker compose exec -T hive bash -c \
    "cd /data/hive && $HIVE_ENV hive $HIVE_ARGS -f /hive/reports/${report}.hql 2>/tmp/hive-${report}.log" \
    || { echo "!! report $report failed:"; docker compose exec -T hive tail -5 "/tmp/hive-${report}.log"; exit 1; }
  docker compose exec -T hive bash -c \
    "cat /report/${report}/* > /report/${report}.csv && rm -rf /report/${report}"
  echo "   wrote report/${report}.csv ($(wc -l < "report/${report}.csv") lines)"
done

echo ">> Reports written to ./report/"
