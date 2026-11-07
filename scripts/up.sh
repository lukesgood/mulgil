#!/usr/bin/env bash
# Bring up the single-laptop fixture.
set -euo pipefail
cd "$(dirname "$0")/../compose"
[ -f .env ] || { echo "compose/.env missing — cp .env.example .env and edit"; exit 1; }
docker compose up -d
echo "SeaweedFS S3  : http://localhost:8333"
echo "Iceberg REST  : http://localhost:8181"
echo "Trino         : http://localhost:8080"
