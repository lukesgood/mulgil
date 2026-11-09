# console — specifications only

The operations console is part of Sumun's commercial edition; its source
lives in **sumun `ee/console`** (ADR 0006). This directory keeps the public
specifications so the console stays a contract that can be implemented by
anyone, including an outside team, against `../ops/API.md`.

## Screens (seven, fixed)
| # | Screen | Phase | Note |
|---|---|---|---|
| 1 | Overview | 2a | status line, capacity, cost, violations, alerts |
| 2 | **Sources & queries** | 2a | catalog connections, source load, query history (no SQL text), resource groups; storage backends as a tab |
| 3 | Tables — landing zone | 2b | hidden when the landing zone is not installed |
| 4 | Pipelines | 2b | hidden likewise |
| 5 | Cost (Chisu) | 3 | per profile, per table, per caller |
| 6 | Alerts | 2a | bundled rules incl. source-load rules |
| 7 | Governance | 3 | Sumun usage, read-only via `GET /usage/export` |

## Not screens, ever
SQL editor or query execution · pods/logs (k9s, Lens) · DAG authoring
(Airflow) · users/permissions (IdP, catalog) · policy editing (Sumun console).
