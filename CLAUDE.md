# Mulgil — working notes for Claude

Mulgil (물길) is the reference medallion lakehouse that feeds Sumun
(lukesgood/sumun). It is NOT a product: glue, dbt models and deployment
profiles over SeaweedFS, Trino/Athena, Polaris, dbt and Airflow.

## Non-negotiables
- No Mulgil-specific API, UI or scheduler. Such a need goes upstream or to Sumun (ADR 0001).
- One dbt project for all profiles. A model that only works on one target is a bug.
- PII is tagged in dbt `meta.pii`, never masked in Silver/Gold — masking is Sumun's per-caller job.
- Gold tables carry a data contract (owner, sla_hours, contract) in schema.yml meta.
- Seeds are synthetic. No customer schemas or records, ever.
- No credentials in compose, Helm values or Terraform — `.env.example` only.
- No Spark without an ADR (ADR 0003). Three profiles only (ADR 0002).

## Layout
dbt/ (shared) · compose/ (laptop fixture) · helm/mulgil/ (sovereign) ·
terraform/aws-serverless/ · terraform/aws-trino/ · docs/adr/ · scripts/
