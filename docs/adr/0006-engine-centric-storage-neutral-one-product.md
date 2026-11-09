# ADR 0006 — Engine-centric, storage-neutral; Mulgil is Sumun's execution layer

Status: accepted · Date: 2026-11-09 · Supersedes ADR 0002 (profiles); amends
ADR 0004 (console location) and ADR 0005 (SeaweedFS features, storage exit test)

## Context
ADR 0005 moved the entry model to "connect first, land progressively" but
left the product standing on an object store (SeaweedFS). Research on the
2026 market (Starburst Enterprise Intelligence Platform, Immuta Agentic Data
Access, MCP gateways) shows that every incumbent is tied to its own platform
and that the open position is *data-layer enforcement, on-prem/air-gapped,
Apache-licensed, documents and tables under one policy, Korean regulation,
small footprint*. Standing on a storage product of our own would recreate
the incumbents' weakness and keep half of ADR 0005's hedges (single
maintainer, exit test, optional features) alive for no product reason.

If connection is first, the centre is what connects: the distributed query
engine. Storage is one of the things connected.

## Decision

### 1. One product, two layers
Sumun is the product. Mulgil is **Sumun's execution and operations layer**:
the engine deployment, source-catalog templates, optional landing zone, and
the operations console's API. Mulgil is not marketed as a product and has no
positioning of its own; customers buy Sumun, "with engine included" when they
have none. Both repositories and both names stay (public engine layer,
private server + `ee/`).

### 2. Engine at the centre
```
                 agents · apps · BI
                        │
   Sumun server — policy, tiers A/B, audit, budgets, usage/export
                        │
   ┌─ Mulgil ──────────────────────────────────────────────┐
   │  distributed query engine (Trino) · access control    │
   │  (OPA bundle rendered by Sumun) · resource groups ·    │
   │  event listener · (optional) Trino Gateway            │
   └──┬───────────┬────────────┬──────────────┬────────────┘
   RDB · DW    Kafka · ES    Hive · Delta   Iceberg landing zone (optional)
  (customer)   (customer)    (customer)      on ANY S3-compatible store (BYO)
```
Agents see only Sumun. Sumun decides tier A (landing zone, documents) or
tier B (source catalogs) and the engine enforces it.

### 3. Storage is the customer's
- The landing zone (Iceberg + Polaris + dbt template) is an **optional
  module** and sits on whatever S3-compatible store the customer has — S3,
  MinIO (their licence), Ceph RGW, SeaweedFS. No storage-specific feature is
  required anywhere.
- SeaweedFS is demoted to **storage option A**: a reference configuration
  with its own infrastructure guide for sovereign customers who have no
  object store. Its specific features (filer events, mount, EC, remote.sync)
  are documented inside option A only.
- The storage exit test of ADR 0005 is withdrawn; there is no dependency to
  exit from. Document ingestion uses S3 event notifications or polling,
  never filer-specific events.

### 4. Profiles are engine profiles (supersedes ADR 0002)
| Profile | Engine | Storage (if landing zone) | Tier B |
|---|---|---|---|
| `trino-k8s` (default) | Trino on Kubernetes — on-prem, air-gapped or EKS | any S3-compatible | full |
| `athena` | Athena (managed Trino-family) — AWS-only, small, low concurrency | S3 Tables | Bronze landing only via Athena Federated Query; agent tier-B access not supported |
| (none) | customer's Starburst · Snowflake · Databricks | customer's | via Sumun adapter |

`sovereign` and `aws-trino` differed only in network and storage values and
are folded into `trino-k8s`. `byop` is the adapter's job, not a profile.

### 5. Console: code in Sumun `ee/`, API spec public here
The operations console (seven screens) is a commercial asset; its source
moves to sumun `ee/console`. Mulgil keeps the screen specifications,
`mulgil-ops` API spec and implementation, so the open repository alone does
not yield a finished engine-operations console. Screens are re-ordered for
the engine-centric product: Overview · **Sources & queries** (new: catalog
connections, source load, query history, resource groups; storage backends
are a tab) · Tables (landing zone, hidden when not installed) · Pipelines ·
Cost (Chisu) · Alerts · Governance. No query execution anywhere in the console.

### 6. Enforcement: OPA first
Tier-B enforcement is attempted first with Trino's Open Policy Agent access
control plugin, Sumun rendering policy tables into OPA bundles. A custom
SystemAccessControl plugin is the fallback, `rules.json` the last fallback.
Spike in the first week of Phase 2a (sumun ADR 0005).

### 7. Phase order
Phase 2a = engine deployment, federation, tier-B enforcement, console
Overview/Sources/Alerts. Phase 2b = landing zone, tier A tables, console
Tables/Pipelines. Phase 3 = row filters, cost/governance screens, Trino
Gateway, SeaweedFS option-A package.

### 8. Positioning guard
Trino is "the engine" in all product text, never a product name. Mulgil has
no tagline. Feature lists start with agent governance. Starburst, Snowflake,
Databricks and Athena appear in the supported-engines table, never in a
competitor column. The console never contains a SQL editor.

## Consequences
- `distro/BOM.yaml`: `storage` becomes a pluggable slot; SeaweedFS is one
  option; Trino Gateway optional; console entries removed (moved to sumun).
- `console/` here holds specs only; `ops/` stays.
- Guides: `00-architecture` restructured around the engine; `02-sovereign`
  becomes "storage option A: SeaweedFS"; sizing leads with the engine.
- README no longer describes Mulgil as a package customers buy.
- Hedges that remain: source load (resource groups, read replicas), tier-B
  weakness disclosure, Trino upstream (OPA plugin stability, `rules.json`
  fallback), solo capacity (2a/2b split, 60% rule).
