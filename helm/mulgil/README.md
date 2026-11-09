# helm/mulgil — `trino-k8s` profile (default)

Umbrella chart for the engine layer on any Kubernetes — on-prem, air-gapped,
or EKS (see `EKS.md`): Trino (resource groups `governed`/`federated`/
`maintenance`, OPA access-control hook, event listener), source-catalog
templates from `engine/catalogs/`, Prometheus + Alertmanager, `mulgil-ops`,
PostgreSQL (`mulgil_ops` schema; also Airflow metadata), and Sumun as a
sub-chart reference. Optional: landing zone (Polaris, Airflow, dbt runner —
needs an S3-compatible endpoint the customer provides), Trino Gateway,
Grafana (unmodified image), SeaweedFS as storage option A (`storage/seaweedfs`).

Versions come from `distro/BOM.yaml`. There is no separate `sovereign` or
`aws-trino` chart any more (ADR 0006); they are value files of this chart.
