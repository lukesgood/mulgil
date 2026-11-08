# console — Mulgil integrated management UI

Next.js. Talks only to `mulgil-ops`. Shares a design-system package and
OIDC login with Sumun's frontend so a customer sees one product.

## Screens (Phase 2, fixed at seven — ADR 0004)
1. Overview — status line, capacity, month-to-date cost, contract violations, open alerts
2. Tables — Bronze/Silver/Gold list; owner, PII tags, contract, freshness, health; maintenance run/schedule
3. Pipelines — dbt run history, failed models, re-run
4. Cost (Chisu) — per profile, per table, per caller
5. Storage — buckets, nodes, volumes, replication, disk trend
6. Alerts — rules, channels, history
7. Governance — Sumun callers, budgets, masking status (read-only embed)

## Not screens
Pods/logs → k9s or Lens · SQL → MCP client or Trino UI · DAGs → Airflow ·
Users/permissions → IdP and Polaris. Each gets a link, not a page.

`screens/` holds one markdown spec per screen (data shown, ops endpoints,
empty/error states) before any component is written.
