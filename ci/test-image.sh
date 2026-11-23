#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports
container=$(docker create "$1" sh -ec '
    mkdir -p /tmp/aceest-results
    export COVERAGE_FILE=/tmp/aceest-results/.coverage
    python -m coverage run --source=app,ACEest_Fitness -m pytest -p no:cacheprovider \
        --junitxml=/tmp/aceest-results/junit.xml
    python -m coverage xml --omit="*/tests/*" -o /tmp/aceest-results/coverage.xml
')
trap 'docker rm -f "$container" >/dev/null' EXIT
status=0
docker start -a "$container" || status=$?
docker cp "$container:/tmp/aceest-results/." reports/
exit "$status"
