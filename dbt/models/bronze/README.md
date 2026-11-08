# Bronze — append-only landing

Two kinds of Bronze model:

- **Seeded / landed** (`bronze_*.sql` over seeds or landing files): run on every profile.
- **Federated ELT** (`bronze_src_*.sql`): `SELECT` from a Trino source
  catalog (`{{ source('crm_pg', 'customers') }}`) materialised as an Iceberg
  table. Profile-scoped — declare in schema.yml:

  ```yaml
  models:
    - name: bronze_src_crm_customers
      meta:
        profiles: [sovereign, aws-trino]   # not aws-serverless (ADR 0005)
        source_kind: federated
  ```

  Use `incremental` with a watermark column; never `full_refresh` against a
  production source without the source DBA. Queries run in Trino's
  `federated` resource group (set `trino.source=sumun-tier-b` is for agents;
  dbt sets `source=dbt`, selector falls to `governed` — add a `dbt` selector
  if the source needs the cap).
