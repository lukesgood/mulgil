# helm/mulgil — `sovereign` profile

Umbrella chart for the on-prem / air-gapped package: SeaweedFS (master,
volume, filer + S3 + optional built-in Iceberg REST), Apache Polaris (default
catalog), Trino (with resource groups and source-catalog templates), Airflow,
PostgreSQL (filer backend, Airflow metadata, `mulgil_ops` schema), Prometheus,
Alertmanager, `mulgil-ops`, console, and Sumun as a sub-chart reference.
Optional: Grafana (unmodified image), `cold_tier: s3` hybrid tiering.

Versions come from `distro/BOM.yaml`; `values-sovereign.yaml` lists the
knobs. The AWS profiles are not Helm charts — see `terraform/`.
