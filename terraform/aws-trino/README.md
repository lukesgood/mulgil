# terraform/aws-trino — full feature set on AWS

S3 · Apache Polaris on EKS (default catalog) · Trino on EKS (fault-tolerant
execution, S3 exchange, `governed`/`federated`/`maintenance` resource groups)
· Airflow on EKS · Prometheus/Alertmanager · mulgil-ops + console. Roughly
$650–750/month before the first query.

Choose this over `aws-serverless` for high agent concurrency, sub-second
interactive latency, or when agents must query existing RDBs/warehouses
directly (tier B). Trino `rules.json` and the T8 access-control plugin are
driven by Sumun's policy tables.

Scaffold.
