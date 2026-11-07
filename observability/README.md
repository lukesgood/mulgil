# observability

Signals Mulgil emits; no UI of its own. Read by Sumun's ops module (Chisu) and
by Grafana for customers without Sumun.

- `prometheus/` — scrape config for SeaweedFS, Trino, Airflow; alert rule defaults
- `grafana/` — default dashboards (cluster health, table growth, query cost)
- `events/` — webhook payload spec for pipeline failures and SLA breaches
- `cost/` — scripts that extract per-table storage (Iceberg metadata) and
  per-query scan bytes (Trino event listener / Athena history) to CSV/JSON

Scaffold; contents land with the first compose bring-up.
