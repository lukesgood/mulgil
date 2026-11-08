# terraform/aws-serverless — lightweight AWS-only profile

S3 Tables (Iceberg REST, automatic compaction) · Athena workgroup `mulgil` ·
Lake Formation permissions · Step Functions schedule for `dbt run` via
dbt-athena · optional MWAA.

For AWS-only customers under roughly 100 TB with low agent concurrency
(ADR 0005). Fixed cost near zero; $5 per TB scanned. Lake Formation receives
the row filters and column masks Sumun generates, so engineers querying
Athena directly stay under the same governance as agents.

Limits: federation is Athena Federated Query (Lambda connectors) for Bronze
landing only — tier-B agent access is not supported here
(`federation.agent_access` forced false). Promotion to `aws-trino` changes
the dbt profile only and moves no data.

Scaffold. Modules land with the first AWS engagement.
