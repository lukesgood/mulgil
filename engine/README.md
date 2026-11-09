# engine — Trino configuration that Mulgil ships

The centre of the layer (ADR 0006). Everything here is rendered into the
`trino-k8s` chart and the compose fixture.

- `resource-groups/groups.json` — `governed` (tier A, default), `federated`
  (tier B: concurrency 4, CPU 30 min/hour), `maintenance` (mulgil-ops)
- `catalogs/*.properties.example` — source catalog templates (PostgreSQL,
  MySQL, Oracle, SQL Server, Kafka, Elasticsearch, Hive) with conservative
  defaults: read-only credentials, read replica recommended, pushdown on,
  writes off. Credentials from `.env` only
- `access-control/` (to land in Phase 2a) — OPA plugin config; the bundle is
  rendered by Sumun. Fallback `rules.json` generator lives in Sumun too
- `event-listener/` (Phase 2a) — query events to the audit/cost path

The landing-zone catalog (`iceberg.properties`) is part of the optional
landing module and points at whatever S3-compatible endpoint the customer has.
