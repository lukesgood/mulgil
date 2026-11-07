#!/usr/bin/env bash
# dbt seed + run: Bronze -> Silver -> Gold on the sample data.
set -euo pipefail
cd "$(dirname "$0")/../dbt"
dbt deps
dbt seed --target "${DBT_TARGET:-local}"
dbt run  --target "${DBT_TARGET:-local}"
dbt test --target "${DBT_TARGET:-local}"
