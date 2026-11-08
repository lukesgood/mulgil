# mulgil-ops — the console's only API

FastAPI service. Joins the platform's data sources and performs the few
writes the console is allowed to make (ADR 0004).

## Sources (read)
| Source | Used for |
|---|---|
| Prometheus (PromQL API) | storage, engine and node metrics; charts in the console |
| Iceberg metadata tables (`$snapshots`, `$files`, `$partitions` via Trino/Athena) | table health: small-file ratio, snapshot count, partition skew |
| dbt artifacts (`manifest.json`, `run_results.json`) | models, owners, `meta.pii`, contracts, run history |
| Airflow REST / Step Functions API | pipeline runs |
| SeaweedFS master API | buckets, volumes, replication |
| Cost: AWS CUR, Athena query logs (bytes scanned), on-prem rate card | per-profile, per-table cost; Chisu module |
| Sumun audit DB (read-only role) | per-caller usage and cost attribution |

## Writes (all idempotent, reversible, logged)
- `POST /tables/{t}/maintenance` — `optimize`, `expire_snapshots`, `remove_orphan_files`; executed as an Airflow DAG run or Athena statement, never scheduled here
- `POST /pipelines/{run}/rerun`
- `PUT /alerts/rules` — rendered to Alertmanager/Prometheus rule files

## Not here
Pod operations, log streaming, user management, SQL execution on behalf of users.

## Patterns kept from DataPond 1.x
`metrics.py`: emission is async, never raises, off by default. Cost export to
CloudWatch is an optional sink for the `aws-*` profiles only.
