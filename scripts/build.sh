#!/usr/bin/env bash
# Compile the Scala Spark job inside the scala-build container (sbt package).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_UID="$(id -u)" BUILD_GID="$(id -g)" docker compose build scala-build
BUILD_UID="$(id -u)" BUILD_GID="$(id -g)" docker compose run --rm scala-build

echo ">> Built jar:"
ls -l spark/target/scala-2.12/*.jar
