# Mulgil — working notes for Claude

Mulgil (물길) is **Sumun's execution and operations layer** (lukesgood/sumun
is the product): a distributed query engine deployment (Trino), source-catalog
templates, an optional Iceberg landing zone on any S3-compatible store, the
`mulgil-ops` API, and the console *specifications*. Mulgil is not marketed as
a product and has no tagline (ADR 0006). History: 0001 reference platform →
0004 package + console → 0005 connect-first → 0006 engine-centric.

## Non-negotiables
- Engine at the centre, storage neutral. Nothing here requires a specific
  object store; SeaweedFS is storage option A with its own guide, nothing more.
  No filer events, mounts or vendor features outside option A docs.
- Two engine profiles only: `trino-k8s` (default) and `athena`. A third needs an ADR.
- Policy is written by Sumun; Mulgil provides the place it runs and its
  operation. Mulgil code never creates policy; it renders what Sumun gives
  (OPA bundle, rules.json, resource groups) and reaches Sumun only via
  `GET /usage/export`.
- Tier-B queries run in the `federated` resource group with read-only source
  accounts; templates ship conservative pushdown/concurrency defaults.
- Console code lives in sumun `ee/console`; here only `console/screens/`
  specs and `ops/`. The console never executes SQL. `mulgil-ops` writes are
  maintenance-only, dry-run first, append-only logged; no scheduler (Airflow /
  Step Functions); the poller only collects.
- Landing zone is optional. One dbt project; a Gold model that only works on one
  target is a bug; Bronze ELT over federated sources declares `meta.profiles`.
- PII is tagged in dbt `meta.pii`, never masked in Silver/Gold — masking is Sumun's job.
- Gold tables carry a data contract (owner, sla_hours, contract) in schema.yml meta.
- Seeds are synthetic. No credentials in compose/Helm/Terraform — `.env.example` only.
- No Spark without an ADR (ADR 0003). Every profile matches `distro/BOM.yaml`.
- Trino is "the engine" in product text, never a product name. Everything here is Apache-2.0.

## Layout
distro/ (BOM, profiles) · engine/ (Trino config: resource groups, catalogs, OPA hook) ·
dbt/ (landing-zone template) · ops/ (mulgil-ops API) · console/screens/ (specs only) ·
compose/ (laptop) · helm/mulgil/ (trino-k8s) · terraform/athena/ · storage/seaweedfs/ (option A) ·
observability/ · docs/adr/ · docs/guide/ · scripts/
