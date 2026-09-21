#!/usr/bin/env bash
# Start the Flask web app and wait until it answers on http://localhost:5000.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p report

echo ">> Starting web app..."
docker compose up -d web

for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5000/ || true)
  if [ "$code" = "200" ]; then
    echo ">> Web app ready: http://localhost:5000  (reports: http://localhost:5000/reports)"
    exit 0
  fi
  sleep 2
done

echo "!! Web app did not become ready - recent logs:" >&2
docker compose logs web --tail 50 >&2
exit 1
