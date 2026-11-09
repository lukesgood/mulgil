# distro — what ships

One version, one bill of materials, two engine profiles (ADR 0006).

```
BOM.yaml          pinned versions; engine / landing_zone (optional) / storage (pluggable) / sumun
profiles/
  trino-k8s.yaml  default — helm/mulgil (on-prem, air-gapped, EKS)
  athena.yaml     lightweight AWS-only — terraform/athena
```

Rules: a profile may not pin a version the BOM does not list; the compose
fixture is the smoke test for every BOM change; storage is never pinned as
required — `byo-s3` is the default and SeaweedFS is option A.
