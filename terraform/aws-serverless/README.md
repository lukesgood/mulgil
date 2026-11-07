# terraform/aws-serverless — the AWS default

S3 Tables (Iceberg REST, automatic compaction) · Athena workgroup `mulgil` ·
Lake Formation permissions · Step Functions schedule for `dbt run` via
dbt-athena · optional MWAA.

Fixed cost near zero; $5 per TB scanned. Lake Formation receives the
row filters and column masks Sumun generates from its policy tables, so
engineers querying Athena directly stay under the same governance as agents.

Scaffold. Modules land with the first AWS engagement.
