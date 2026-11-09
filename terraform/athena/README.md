# terraform/athena — lightweight AWS-only profile

Athena workgroup `sumun` (managed Trino-family engine) · S3 Tables for the
landing zone (Iceberg REST, automatic compaction) · Lake Formation permissions
rendered from Sumun policy · Step Functions schedule for `dbt run` via
dbt-athena · optional MWAA.

For AWS-only customers with low agent concurrency (ADR 0006). Fixed cost near
zero; $5 per TB scanned. Federation is Athena Federated Query (Lambda
connectors) for Bronze landing only — agent tier-B access is not supported
here (`federation.agent_access` forced false). Promotion to `trino-k8s`
changes the dbt profile only and moves no data.

Scaffold. Modules land with the first AWS engagement.
