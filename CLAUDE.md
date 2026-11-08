# Mulgil — working notes for Claude

Mulgil (물길) is a medallion lakehouse **package** sold with build
engagements and bundled with Sumun (lukesgood/sumun): a versioned
distribution (BOM, Helm umbrella, Terraform, compose), a dbt template,
build guides, and an integrated management console over SeaweedFS,
Trino/Athena, Polaris, dbt and Airflow. ADR 0004 replaced the earlier
"reference platform, not a product" stance (ADR 0001).

## Non-negotiables
- One console (`console/`), one ops API (`ops/`). The console manages data
  assets — tables, pipelines, cost, storage, alerts — never pods, logs, SQL
  editing, DAG authoring or users (ADR 0004). Link to k9s/Airflow/IdP instead.
- All writes go through `mulgil-ops`, are maintenance-only, idempotent,
  reversible, dry-run first, and recorded append-only in `ops_actions`.
  No Mulgil scheduler for business work: maintenance and dbt run via Airflow
  or Step Functions. The ops poller only collects; it changes nothing outside.
- `mulgil-ops` reaches Sumun through `GET /usage/export` only — never Sumun's DB.
- One console = one profile (v0). Table id = catalog FQN.
- Time series live in Prometheus, alerts in Alertmanager. Grafana is optional
  and never modified (AGPL) — dashboards as JSON only.
- One dbt project for all profiles. A model that only works on one target is a bug.
- Every profile matches `distro/BOM.yaml`. Version drift is a bug.
- PII is tagged in dbt `meta.pii`, never masked in Silver/Gold — masking is Sumun's per-caller job.
- Gold tables carry a data contract (owner, sla_hours, contract) in schema.yml meta.
- Seeds are synthetic. No customer schemas or records, ever.
- No credentials in compose, Helm values or Terraform — `.env.example` only.
- No Spark without an ADR (ADR 0003). Three profiles only (ADR 0002).
- Everything here is public, Apache-2.0. Commercial value is the engagement and Sumun `ee/`.

## Layout
distro/ (BOM, profiles) · dbt/ (shared) · ops/ (mulgil-ops API) · console/ (UI) ·
compose/ (laptop) · helm/mulgil/ (sovereign) · terraform/aws-serverless/ ·
terraform/aws-trino/ · observability/ · docs/adr/ · docs/guide/ · scripts/
