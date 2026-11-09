# `trino-k8s` on EKS — notes

The same chart as on-prem; differences are values only: S3 for the landing
zone (if used), IRSA for the engine service account, Spot workers with
fault-tolerant execution and an S3 exchange bucket, ALB ingress. Roughly
$650–750/month before the first query for three m6i.xlarge workers plus
control plane and NAT. Choose this over `athena` for agent concurrency,
sub-second latency, or when agents must query existing RDBs/warehouses
directly (tier B).
