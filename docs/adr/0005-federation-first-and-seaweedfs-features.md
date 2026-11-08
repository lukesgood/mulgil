# ADR 0005 — Connect first, land progressively: Trino federation and SeaweedFS-specific features

Status: accepted · Date: 2026-11-09 · Amends ADR 0002, 0004

## Context
Until now Mulgil used Trino only as an Iceberg engine and SeaweedFS only as
an S3 endpoint. That left the two reasons for choosing them over Athena and
MinIO unused:

- **Trino** federates PostgreSQL, MySQL, Oracle, SQL Server, Kafka,
  Elasticsearch, MongoDB, Hive, Delta and more behind one SQL endpoint, and
  `INSERT INTO iceberg… SELECT FROM postgresql…` is a complete ELT path.
- **SeaweedFS** handles small files well, emits filer metadata events,
  mounts as a filesystem (`weed mount`), erasure-codes cold data, and tiers
  to remote S3 (`filer.remote.sync`).

Customers in Korean finance and public sector rarely start with a clean
lakehouse. They have operational RDBs, a warehouse, and NAS folders.
Requiring a migration before governance applies delays the first value by
months. Competing on federation features against Starburst or Denodo is not
the goal; applying agent governance to existing data without a migration is.

## Decision

### 1. Entry model: connect → govern → land
Mulgil gains a **federation mode**: Trino + source catalogs + Sumun, with
Iceberg optional on day one. Sources are queryable immediately under
Sumun's governance tier B (sumun ADR 0004); tables that need full governance
(tier A) are landed into Iceberg Gold with Trino ELT through dbt. The
medallion lakehouse remains the destination; it is no longer the
prerequisite.

### 2. Ingestion defaults
| Source kind | Default path | Previously |
|---|---|---|
| RDB / warehouse | Trino ELT via dbt (`source` catalog → Bronze Iceberg model) | Airbyte |
| Files in a legacy NAS path | `weed mount` exposes the landing bucket as a directory; writers change nothing | custom connector |
| Documents dropped into landing | Sumun's ingester subscribes to filer metadata events (`filer.meta.tail`); polling is the fallback | polling |
| SaaS APIs | Airbyte, or the small `connector-sdk` in sumun (SaaS-only now) | connector SDK, broad |
| Streams | Kafka Connect Iceberg Sink, or Trino Kafka connector for tier-B reads | same |

### 3. Source catalog templates
`compose/trino/etc/catalog/*.properties.example` for postgresql, mysql,
oracle, sqlserver, kafka, elasticsearch, hive, with **conservative
defaults fixed**: read-only credentials (read replica recommended),
`max-splits`, per-catalog concurrency, `query.max-execution-time`, and a
dedicated Trino resource group `federated` with CPU and concurrency caps.
Credentials come from `.env` only.

### 4. SeaweedFS-specific features — optional, never required
- Filer events, `weed mount`, erasure coding for Bronze and audit retention,
  and `filer.remote.sync` cold tiering to S3 are **optional features**. The
  product must run with none of them, so SeaweedFS stays replaceable.
- `sovereign` gains an optional **hybrid cold tier** (`cold_tier: s3`): hot
  on-prem, cold in S3/Glacier. This is the expected AWS consumption path
  for regulated customers, more than the `aws-serverless` profile.
- Sizing guide: disk formula gains an erasure-coding variant (1.4x instead
  of 2x for cold layers); federation sizing adds source-load limits.

### 5. Catalog default
Apache Polaris becomes the **default** Iceberg catalog for `sovereign` and
`aws-trino`; SeaweedFS's built-in REST catalog is the lightweight option for
the compose fixture and small installs. Reason: the catalog must not be tied
to the storage vendor (see hedge below).

### 6. Profiles (amends ADR 0002)
- `sovereign` and `aws-trino`: full feature set including federation and
  tier-B agent access.
- `aws-serverless`: **lightweight profile** for AWS-only customers under
  roughly 100 TB with low agent concurrency. Athena Federated Query (Lambda
  connectors) is supported for Bronze landing only; tier-B agent access is
  *not* supported here. Promotion to `aws-trino` changes the dbt profile
  only and moves no data; this is tested.
- The rule "one dbt project, every model runs on every profile" applies to
  **Gold models**. Bronze ELT models that read a federated source are
  profile-scoped and declared so in `schema.yml` (`meta.profiles`).

### 7. Phase 2 split
Phase 2a: Iceberg tables, console Tables and Pipelines screens, T8 at
catalog/table level. Phase 2b: source catalog templates, tier-B policy, T8
column level, console Alerts and Overview. Phase 3 adds hybrid tiering,
erasure coding, cross-DC replication, T8 row filters, Scan Plan API.

## Hedges (decided with this ADR)
- **Storage exit test**: twice a year, copy a fixture from SeaweedFS to
  Ceph RGW (or MinIO where the customer holds a licence), re-register the
  Iceberg catalog, run the dbt tests. Iceberg metadata is path-based, so
  storage is replaceable if paths are preserved. Garage and Ceph RGW stay
  listed as verified alternatives in the sizing guide.
- **Upstream watch**: SeaweedFS is effectively a single-maintainer project.
  BOM pins the version; quarterly upgrade rehearsal; release cadence and
  issue response time are a quarterly check item.
- **Source load**: tier-B queries run in the `federated` resource group;
  console alerts on per-source query time and connection count; a source
  that keeps tripping is moved to ELT landing (one step sideways by design).
- **Positioning**: Trino is named as "the engine" and nothing more in
  product material; the first line of every feature list is agent
  governance. Sumun's adapter interface also lets a Starburst customer run
  Sumun alone — Starburst is a layer below, not a competitor.
- **Solo capacity**: weekly status tracks planned-vs-done; three weeks under
  60% moves Phase 2b to Phase 3. Console specs and the ops API stay complete
  without the UI so the UI can be handed to someone else.
- **Open-source cannibalisation**: Mulgil stays fully Apache-2.0; commercial
  value is Sumun `ee/` plus the build and security-review document package.
  The console directory carries its own LICENSE file so it could move to a
  source-available licence later without touching the rest.

## Consequences
- README and product plan describe Mulgil as "a governed data layer you can
  start without a migration", not as a lakehouse you must build first.
- `connector-sdk` in sumun shrinks to SaaS API sources.
- CLAUDE.md non-negotiables: "one dbt project for all profiles" is narrowed
  to Gold; SeaweedFS features are optional; Polaris is the default catalog.
- Observability event schema gains `source_kind: federated|landed`.
