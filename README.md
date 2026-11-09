# Mulgil (물길)

**The execution layer of [Sumun (수문)](https://github.com/lukesgood/sumun).**
Not a product of its own (ADR 0006).

Sumun is an agent data-access control layer: it decides, in front of the
data, what an AI agent may see on whose behalf and within what budget, and
enforces that in the data layer — row-level security, catalog permissions,
engine access control — with the same policy for documents and tables, all
Apache-licensed, inside air-gapped networks. Mulgil is the place that policy
runs when a customer has no engine of their own:

- a **distributed query engine deployment** (Trino on Kubernetes, or Athena)
  with resource groups, an OPA access-control hook and an event listener,
- **source-catalog templates** for the systems customers already have —
  PostgreSQL, MySQL, Oracle, SQL Server, Kafka, Elasticsearch, Hive — with
  read-only, conservative defaults,
- an **optional landing zone** (Iceberg + Polaris + a dbt medallion template)
  on **any S3-compatible store the customer provides**,
- the **`mulgil-ops` API** behind Sumun's operations console, and the
  console's public specifications,
- **storage option A**: a SeaweedFS reference configuration and infrastructure
  guide for sovereign customers who have no object store at all.

> Agents see only Sumun. Sumun decides tier A (landing zone, documents) or
> tier B (your existing sources). The engine enforces it.

## Governance tiers

| | Tier A — governed | Tier B — federated |
|---|---|---|
| Data | Iceberg landing zone, document collections | any table in a connected source catalog |
| Enforcement | Postgres RLS, catalog permissions, engine access control | engine access control (OPA bundle rendered by Sumun) |
| PII | dbt `meta.pii` tags → per-caller masking | scanned at registration; pattern columns **blocked** |
| Default | in the agent's scope | read-only, aggregate-first, ≤100 rows, out of scope until listed per key |
| Nature | operational access | discovery access — weaker by design, and the security-review package says so |

Moving a table from B to A is one Trino ELT statement into the landing zone.

## Profiles

| Profile | Engine | Landing-zone storage | Tier B |
|---|---|---|---|
| `trino-k8s` (default) | Trino on Kubernetes — on-prem, air-gapped, or EKS (`helm/mulgil`) | any S3-compatible (S3, MinIO under your licence, Ceph RGW, SeaweedFS option A) | full |
| `athena` | Athena — AWS-only, small, low concurrency (`terraform/athena`) | S3 Tables | Bronze landing only; no agent tier-B access |
| none | your Starburst · Snowflake · Databricks | yours | through Sumun's engine adapter |

## Layout

```
distro/           BOM.yaml (pinned versions), profile overlays
engine/           Trino config Mulgil ships: resource groups, source-catalog templates, OPA hook, event listener
dbt/              landing-zone template — Bronze/Silver/Gold, meta.pii, contracts, metrics
ops/              mulgil-ops — the console's only API (spec + implementation)
console/screens/  console specifications (code lives in sumun ee/console)
compose/          single-laptop fixture
helm/mulgil/      trino-k8s chart (+ EKS.md)
terraform/athena/ athena profile
storage/seaweedfs/ storage option A — reference config + infrastructure guide (Korean)
observability/    exporters, alert rule bundle, event schema, optional Grafana JSON
docs/adr/         decisions · docs/guide/ build guides (Korean) · docs/license-review.md
```

## Documentation map

| Want to… | Read |
|---|---|
| understand what is where and why | `docs/guide/00-architecture.md` |
| size the engine or price a profile | `docs/guide/01-sizing.md` |
| build an object store because you have none | `storage/seaweedfs/GUIDE.md` |
| see the console contract | `console/README.md`, `console/screens/`, `ops/API.md` |
| check versions and licenses | `distro/BOM.yaml`, `docs/license-review.md`, `THIRD_PARTY_NOTICES.md` |
| see why a decision was made | `docs/adr/README.md` |
| work on the repo | `CLAUDE.md`, `docs/process/METHOD.md` (in sumun) |

## Quick start

```
cp compose/.env.example compose/.env
scripts/up.sh          # Trino, Postgres, (optional) SeaweedFS for the landing zone
scripts/seed.sh        # dbt seed + run on the fixture
```

Point Sumun's `dev` profile at `http://localhost:8080` (Trino).

## What crosses into Sumun

Mulgil produces four things Sumun reads and never writes: PII column tags
(`meta.pii`), data contracts and metric definitions on Gold, lineage (dbt
manifest), freshness (snapshot timestamps). Sumun reaches Mulgil's console
data only through `GET /usage/export`, never the other way into Sumun's DB.

## Sample data
Fictional only; Korean-format PII in seeds is synthetic and checksum-valid so
Sumun's masking tests have something to catch.

## License
Apache-2.0. Upstream components keep their own licenses — see
`THIRD_PARTY_NOTICES.md` and `docs/license-review.md`. The operations console
source is commercial and lives in sumun `ee/`.
