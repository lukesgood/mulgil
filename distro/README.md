# distro — the Mulgil package

What a customer receives: one version, one bill of materials, three ways to
deploy it.

```
BOM.yaml          pinned component versions — the package version lives here
profiles/         per-profile overlays that reference the BOM
  sovereign.yaml  → helm/mulgil (values-sovereign.yaml)
  aws-serverless.yaml → terraform/aws-serverless
  aws-trino.yaml  → terraform/aws-trino
```

Rules (ADR 0004):
- A profile may not pin a version the BOM does not list.
- The compose fixture is the smoke test for every BOM change.
- Sumun is a bundled component; its version constraint is in the BOM.

`scripts/check-bom.sh` (to be written) diffs profile pins against the BOM in CI.
