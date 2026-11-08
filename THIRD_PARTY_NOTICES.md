# Third-party components

| Component | License | Default |
|---|---|---|
| SeaweedFS | Apache-2.0 | yes |
| Trino | Apache-2.0 | yes |
| Apache Polaris | Apache-2.0 | optional |
| dbt-core, dbt-trino, dbt-athena | Apache-2.0 | yes |
| Apache Airflow | Apache-2.0 | sovereign / aws-trino |
| PostgreSQL | PostgreSQL License | yes |
| MinIO | AGPL-3.0 | **not included** — bring your own if already licensed |
| Prometheus, Alertmanager | Apache-2.0 | yes |
| Grafana | AGPL-3.0 | **optional**, unmodified upstream image only; Mulgil ships dashboards as JSON and never a modified build |
| Trino bundled JDBC drivers | PostgreSQL JDBC BSD-2 · mssql-jdbc MIT · Oracle ojdbc **Oracle FUTC** (no extra fee may be charged for the driver; none is) · MySQL: Connector/J GPL-2.0+Universal FOSS Exception or MariaDB Connector/J LGPL-2.1 — verify per pinned Trino version | with Trino |
| Airbyte | platform **ELv2**, connectors MIT | **not bundled** — optional, SaaS-API sources only, customer-installed; MSP operation of it needs legal review (ELv2 managed-service clause) |
| dbt Fusion binary / dbt platform | ELv2 / commercial | **not included** — only `dbt-core` (Apache-2.0) is bundled |
| Ollama (sovereign, optional) | MIT | model weights carry their own licenses — see docs/model-licenses.md generated at install |
| Garage, Ceph RGW | AGPL-3.0 / LGPL-GPL | **not included** — listed as verified alternatives for the storage exit test only |

Full review with obligations and actions: `docs/license-review.md`.
