# Mulgil (물길)

**A reference medallion lakehouse on open components — not a product.**

Mulgil is the waterway: it carries data from sources through Bronze, Silver
and Gold on Apache Iceberg, using SeaweedFS, Trino, Apache Polaris, dbt and
Airflow. [Sumun (수문)](https://github.com/lukesgood/sumun) is the gate at
the end of it — the governed tool server that decides which agents and
applications may drink from Gold.

> Mulgil carries the data. Sumun decides who drinks.

Mulgil exists for three jobs, in this order:

1. **Test fixture** for Sumun — leak regression tests and `query_metric`
   need real Gold tables with PII-tagged columns.
2. **Demo** — the whole flow, sources → Gold → agent, on one laptop.
3. **Build template** for on-prem and air-gapped lakehouse engagements.

It is glue and sample models over upstream open-source projects. If a change
makes Mulgil look like a product — its own API, its own UI, its own
scheduler — it belongs upstream or in Sumun, not here.

## Stack

| Layer | Component | Why this one |
|---|---|---|
One dbt project, three deployment profiles. The models, tests, PII tags and
metric definitions are identical; only the target changes.

| Layer | `sovereign` (on-prem, air-gapped) | `aws-serverless` (AWS default) | `aws-trino` (AWS, large or low-latency) |
|---|---|---|---|
| Object store | SeaweedFS | S3 | S3 |
| Iceberg catalog | SeaweedFS built-in REST, or Polaris | S3 Tables (built-in REST) | Polaris |
| Query + transform engine | Trino on Kubernetes | Athena (Trino-based engine) | Trino on EKS |
| dbt adapter | dbt-trino | dbt-athena | dbt-trino |
| Orchestration | Airflow on Kubernetes | Step Functions or scheduled CI; MWAA optional | Airflow on EKS |
| Iceberg maintenance | Trino `optimize` / `expire_snapshots` via Airflow | S3 Tables automatic compaction; Athena `OPTIMIZE`/`VACUUM` | Trino via Airflow |
| Second-layer governance (engineers via SQL) | Trino `rules.json` generated from Sumun policies | Lake Formation permissions generated from Sumun policies | Trino `rules.json` |
| Ingestion (optional) | Airbyte, Kafka Connect Iceberg Sink | Airbyte, DMS, Glue, Kinesis | Airbyte, Kafka Connect |

Spark is deliberately absent. Trino and Athena cover writes, `MERGE` and
table maintenance; add Spark only when a workload proves it needs it.

**Why serverless is the AWS default.** Trino on EKS costs roughly $650–750
a month before the first query (three m6i.xlarge nodes, EKS control plane,
NAT); Athena costs $5 per TB scanned and nothing idle. Break-even is around
130 TB scanned a month, which mid-size Gold-layer workloads rarely reach.
Per-query scan bytes also give Sumun exact per-caller cost attribution.
Choose `aws-trino` for high agent concurrency or sub-second latency.

Spark is deliberately absent. Trino covers writes, `MERGE`, and table
maintenance; add Spark only when a workload proves it needs it.

## Layout

```
dbt/                    shared — Bronze, Silver, Gold models; seeds; metric definitions
  models/bronze         raw, append-only
  models/silver         conformed entities; PII columns tagged
  models/gold           metric tables with data contracts
compose/                single-laptop fixture (a shrunken `sovereign`)
  seaweedfs/            S3 gateway + Iceberg REST catalog
  trino/                catalog config for Iceberg over SeaweedFS
helm/mulgil/            `sovereign` on Kubernetes (values-sovereign.yaml)
terraform/aws-serverless/  S3 Tables, Athena, Lake Formation, Step Functions
terraform/aws-trino/       S3, Polaris, Trino on EKS, Airflow
observability/          exporter config, Grafana defaults, event payload specs, cost extracts
docs/adr/               decisions
docs/guide/             build guide (Korean): architecture, sizing, profiles, modeling, operations
scripts/                bring-up, seed, teardown
```

## What crosses the boundary into Sumun

Mulgil produces four things Sumun reads and never writes:

| Mulgil produces | Sumun uses it for |
|---|---|
| PII column tags on Silver and Gold (Iceberg column properties `pii=rrn`, `pii=phone`, …) | Tag-driven masking policies instead of per-table hand-written rules |
| Data contracts on Gold (schema, owner, SLA) and dbt metric definitions | `query_metric` — one definition shared by BI and agents |
| Lineage (dbt manifest, optionally OpenMetadata) | Provenance in the audit log, down to source |
| Freshness (Iceberg snapshot timestamps, dbt run state) | `as_of` on every answer; stale data labelled or refused |

Agents see Gold only. Bronze and Silver are reachable by engineers through
Trino under the same policy tables Sumun enforces.

## Quick start

```
cp compose/.env.example compose/.env
scripts/up.sh          # SeaweedFS, Trino, Airflow, Postgres
scripts/seed.sh        # dbt seed + run: Bronze → Silver → Gold on sample data
```

Then point Sumun's `dev` profile at `http://localhost:8080` (Trino) and
`http://localhost:8181` (Iceberg REST).

## Sample data

Fictional orders, customers and products only. No customer schemas, no
real records. Korean-format PII (주민등록번호, 휴대전화) in the seed is
synthetic and checksum-valid so Sumun's masking tests have something to
catch.

## License

Apache-2.0. Upstream components keep their own licenses; MinIO (AGPL) is
not included by default — SeaweedFS is. See THIRD_PARTY_NOTICES.md once
the first compose file lands.
