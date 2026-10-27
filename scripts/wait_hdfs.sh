#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

echo ">> Waiting for HDFS (NameNode + DataNode)..."
for _ in $(seq 1 100); do
  safemode=$(docker compose exec -T namenode hdfs dfsadmin -safemode get 2>/dev/null || true)
  report=$(docker compose exec -T namenode hdfs dfsadmin -report 2>/dev/null || true)
  if echo "$safemode" | grep -q OFF &&
     echo "$report" | grep -Eq 'Live datanodes \([1-9]'; then
    echo ">> HDFS is ready"
    exit 0
  fi
  sleep 3
done

echo "!! HDFS did not become ready in time - check 'docker compose logs namenode datanode'" >&2
exit 1
