# ADR 0002 — Three profiles; Athena is the AWS default

Status: accepted · Date: 2026-11-08

## Context
Trino on EKS costs about $650–750/month idle. Athena costs $5/TB scanned.
Break-even is ~130 TB scanned/month, above typical Gold-layer workloads
for 300–3,000-person customers. Athena's engine is Trino-based, so dbt
models port with minor dialect changes; S3 Tables compacts automatically;
Lake Formation supplies row/column security.

## Decision
- `sovereign`: SeaweedFS + Trino + Airflow on Kubernetes.
- `aws-serverless` (default on AWS): S3 Tables + Athena + dbt-athena +
  Step Functions.
- `aws-trino`: S3 + Polaris + Trino on EKS + Airflow, for high concurrency
  or sub-second latency.
- One dbt project for all three; only the target differs.

## Consequences
- Sumun needs two engine adapters (Trino, Athena) and two policy exporters
  (Trino rules.json, Lake Formation).
- Per-caller cost attribution is exact on Athena (scan bytes) and
  estimated on shared Trino.
