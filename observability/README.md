# observability

Signals Mulgil emits and the engines that hold them. The screen is Sumun's operations
console (code in sumun `ee/console`, specs in `console/`), fed by `mulgil-ops` (`ops/`); Grafana is an optional,
unmodified add-on for operators (ADR 0004).

- `prometheus/` — scrape config for SeaweedFS, Trino, Airflow, PostgreSQL, node exporters; retention 90d
- `alerts/` — bundled Alertmanager/Prometheus rules (infra guide §10.2 + data rules: contract SLA breach, dbt failure, table health bad, cost forecast >120%). Expressions are locked; thresholds are edited from the console
- `events/` — webhook payload spec for pipeline failures and SLA breaches (`source_kind: federated|landed`)
- `grafana/` — optional dashboards as JSON only
- `cost/` — rate-card schema and extraction notes; computation lives in `ops/`

Scaffold; contents land with the first compose bring-up.
