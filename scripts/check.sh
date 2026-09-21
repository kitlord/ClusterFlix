#!/usr/bin/env bash
# Verify every stage of the pipeline.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; failures=$((failures + 1)); }

echo "== CineMatch pipeline check =="

echo "1/5 HDFS contains the dataset"
if docker compose exec -T namenode hdfs dfs -test -e /data/raw/ratings/ratings.csv 2>/dev/null &&
   docker compose exec -T namenode hdfs dfs -test -e /data/raw/movies/movies.csv 2>/dev/null; then
  ratings_rows=$(docker compose exec -T namenode hdfs dfs -cat /data/raw/ratings/ratings.csv 2>/dev/null | wc -l)
  pass "HDFS has ratings.csv ($ratings_rows rows incl. header) and movies.csv"
else
  fail "dataset missing in HDFS (run: make setup)"
fi

echo "2/5 Spark produced an RMSE"
rmse=$(docker compose exec -T namenode hdfs dfs -cat "/output/rmse/part-*" 2>/dev/null | grep -a RMSE | head -1)
if [ -n "$rmse" ]; then
  pass "RMSE: $rmse"
else
  fail "no RMSE found in HDFS /output/rmse (run: make train)"
fi

echo "3/5 MongoDB contains recommendations"
count=$(docker compose exec -T mongo mongosh --quiet cinematch \
  --eval 'db.recommendations.countDocuments({})' 2>/dev/null | tr -dc '0-9')
if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
  pass "cinematch.recommendations has $count documents (one per user)"
else
  fail "no recommendations in MongoDB (run: make train)"
fi

echo "4/5 Hive reports exist and are non-empty"
missing=0
for report in most_rated avg_rating_by_genre rating_distribution; do
  if [ -s "report/${report}.csv" ]; then
    echo "         report/${report}.csv: $(wc -l < "report/${report}.csv") lines"
  else
    echo "         report/${report}.csv missing or empty"
    missing=1
  fi
done
if [ "$missing" -eq 0 ]; then
  pass "all 3 reports present in ./report/"
else
  fail "reports missing (run: make report)"
fi

echo "5/5 Flask returns HTTP 200"
home_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/ 2>/dev/null || true)
reports_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/reports 2>/dev/null || true)
if [ "$home_code" = "200" ] && [ "$reports_code" = "200" ]; then
  pass "GET / -> 200, GET /reports -> 200 (http://localhost:5000)"
else
  fail "GET / -> ${home_code:-none}, GET /reports -> ${reports_code:-none} (run: make serve)"
fi

echo "== $failures check(s) failed =="
exit "$failures"
