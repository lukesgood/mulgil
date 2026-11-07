# helm/mulgil

`sovereign` profile on Kubernetes: SeaweedFS (master/volume/filer + S3 +
Iceberg REST), Trino, Airflow, PostgreSQL (filer backend and Airflow
metadata). Chart scaffold; `values-sovereign.yaml` lists the knobs.

The AWS profiles are not Helm charts — see `terraform/aws-serverless` and
`terraform/aws-trino`.
