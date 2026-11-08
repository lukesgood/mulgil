# Mulgil (물길)

**A governed medallion lakehouse package on open components — with
[Sumun (수문)](https://github.com/lukesgood/sumun) built in.**

Mulgil is the waterway: it carries data from sources through Bronze, Silver
and Gold on Apache Iceberg, using SeaweedFS, Trino or Athena, Apache
Polaris, dbt and Airflow. Sumun is the gate at the end of it — the governed
tool server that decides which agents and applications may drink from Gold.

> Mulgil carries the data. Sumun decides who drinks.

Mulgil is delivered as a **package** (ADR 0004): one bill of materials, three
deployment profiles, a dbt template, build guides, and an integrated
management console that manages the data assets — tables, pipelines, cost,
storage, alerts — in one place. It is built for organisations that do not
yet have a lakehouse and want one that is governed for AI agents from day
one; organisations that already have a platform use Sumun alone.

What Mulgil is not: a pod viewer, a SQL editor, a DAG editor or a user
directory. Those stay with k9s, your MCP client, Airflow and your IdP, and
the console links to them.

Everything in this repository is public and Apache-2.0. Revenue comes from
build engagements, support and Sumun's commercial extensions.

## Stack

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

## Layout

```
distro/                 the package: BOM.yaml (pinned versions = product version), profile overlays
dbt/                    shared — Bronze, Silver, Gold models; seeds; metric definitions
ops/                    mulgil-ops — the console's only API; table maintenance, cost, pipeline state
console/                integrated management UI (seven screens; see console/README.md)
compose/                single-laptop fixture (a shrunken `sovereign`)
helm/mulgil/            `sovereign` on Kubernetes (values-sovereign.yaml)
terraform/aws-serverless/  S3 Tables, Athena, Lake Formation, Step Functions
terraform/aws-trino/       S3, Polaris, Trino on EKS, Airflow
observability/          exporter config, alert rules, event payload specs, cost extracts
docs/adr/               decisions
docs/guide/             build guides (Korean): architecture, sizing, sovereign cluster
scripts/                bring-up, seed, teardown
```

## Integrated management console

| Screen | Shows | Can do |
|---|---|---|
| Overview | status, capacity, month-to-date cost, contract violations, open alerts | — |
| Tables | layer, owner, PII tags, contract, freshness, health (small files, snapshots) | run or schedule `optimize`, `expire_snapshots`, orphan cleanup |
| Pipelines | dbt run history, failed models, SLA breaches | re-run |
| Cost (Chisu, 치수) | per profile, per table, per caller | — |
| Storage | buckets, nodes, volumes, replication, disk trend | — |
| Alerts | rules, channels, history | edit rules |
| Governance | Sumun callers, budgets, masking status | — (read-only) |

Time series live in Prometheus and alerts in Alertmanager; the console draws
its own charts from PromQL. Grafana is an optional add-on for operators.

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
