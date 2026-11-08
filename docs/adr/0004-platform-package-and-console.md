# ADR 0004 — Mulgil is a lakehouse package with its own console

Status: accepted · Date: 2026-11-08 · Supersedes ADR 0001 in part

## Context
ADR 0001 made Mulgil a reference platform with no API, UI or scheduler of
its own, so that Sumun could stay narrow. Two things changed:

1. **The customer order is platform first.** Customers who already run a
   lakehouse (segment A) buy Sumun alone. Customers without one (segment B —
   most Korean finance and public-sector accounts we meet) cannot use Sumun
   until a platform exists. Segment B is the natural entry point for an MSP,
   and it buys a *package*, not a reference repo.
2. **A package needs integrated management.** Operators of segment B want one
   place to see table health, pipeline state, storage and cost. Sending them
   to Grafana, Trino UI, Airflow UI and `weed shell` separately is not a
   product.

DataPond 1.x tried to meet the second need with a hand-built Kubernetes pod
viewer (≈2,300 lines across `api/services.py` and `frontend/components/
{services,infra,dashboard}`), left Prometheus/Grafana as unused Helm values
("no template consumes this yet"), and emitted cost metrics only to
CloudWatch. It never managed data assets (compaction, snapshots, contracts).
That is the failure to avoid: a console that re-implements infrastructure
tooling and ignores the data.

## Decision
Mulgil becomes a **lakehouse package**: a versioned distribution (BOM +
Helm umbrella / Terraform / compose), a dbt template, build guides, and an
**integrated management console**. Sumun is a component of the package.

### What the console manages
Data assets, not infrastructure:

| Area | Reads | Writes |
|---|---|---|
| Overview | status line, capacity, month-to-date cost, contract violations, open alerts | — |
| Tables | layer, owner, PII tags, contract, freshness, health (small files, snapshots) | run/schedule `optimize`, `expire_snapshots`, orphan cleanup |
| Pipelines | dbt run history, failed models, SLA breaches | re-run |
| Cost | per profile (on-prem equivalent / Athena scan / EKS), per table, per caller (from Sumun audit) | — |
| Storage | buckets, nodes, volumes, replication, disk trend | — |
| Alerts | rules, channels, history | rules |
| Governance | Sumun callers, budgets, masking status (read-only embed) | — |

Not in the console, by decision: pod and log viewers (k9s/Lens), SQL
editor (MCP clients, Trino UI), DAG authoring (Airflow), user and
permission management (IdP, Polaris). The console links to these.

### How it is built
- **Own UI** (`console/`, Next.js) sharing a design system package and OIDC
  with Sumun's frontend. A package sold to customers needs its own face.
- **One backend, `mulgil-ops`** (`ops/`, FastAPI): the console's only API.
  It joins Prometheus, Iceberg metadata tables, dbt artifacts, SeaweedFS
  master API, cost sources (CUR, Athena query logs, on-prem rate card) and
  Sumun's audit DB (read-only role). All writes go through it and are
  idempotent and reversible maintenance actions only.
- **Borrowed engines**: Prometheus for time series (console queries PromQL
  and draws its own charts), Alertmanager for alert evaluation and routing.
  Grafana is an *optional* add-on for operators, not the product screen.
- **Scheduling stays in Airflow / Step Functions.** `mulgil-ops` schedules
  maintenance by creating DAG runs, not with a scheduler of its own. Its
  internal poller only *collects* (health, cost, capacity) and never changes
  external state; that is observation, not scheduling.
- **Sumun is reached through its API only** (`GET /usage/export`, aggregated
  and pseudonymised). `mulgil-ops` never connects to Sumun's database.
- **One console instance per profile** in v0; no environment switcher.
- **Chisu (치수)** is the name of the console's cost and capacity module. The
  earlier idea of an ops module inside Sumun is withdrawn (see sumun ADR
  0003): platform cost and resources belong to the platform; Sumun supplies
  per-caller usage only.

### What is kept from ADR 0001
- No Mulgil-specific scheduler.
- Everything in this repo stays Apache-2.0 and public. The console is part
  of the open package; commercial value is the build engagement, support and
  Sumun `ee/`.
- The data boundary into Sumun (PII tags, contracts, lineage, freshness) is
  unchanged.

## Consequences
- Estimated solo effort for all seven screens is about 10 weeks. They are
  split: **Phase 2 — Tables, Pipelines, Alerts, Overview (~6 weeks)**;
  **Phase 3 — Storage, Cost, Governance**, the last two alongside Sumun O2
  (cost attribution) and `GET /usage/export`. The separate "dedicated
  console" item in Phase 3 disappears.
- Table health is computed from Iceberg metadata files read directly from
  object storage, so the console itself does not generate Athena scan cost.
- Prometheus retention is at least 90 days (BOM).
- `distro/BOM.yaml` pins component versions; the package version is the
  product version. A profile that drifts from the BOM is a bug.
- From DataPond 1.x, keep the patterns of `metrics.py` (async, never raises,
  off by default) and the chart components; do not port the pod viewer.
- Grafana remains optional; if bundled, dashboards are JSON only, never a
  modified Grafana build (AGPL).
- CLAUDE.md non-negotiable "no Mulgil-specific API, UI" is replaced by
  "one console, one ops API, data assets only".
