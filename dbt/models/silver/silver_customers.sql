-- Silver: conformed customer entity. PII columns are tagged in schema.yml;
-- Sumun reads those tags to drive masking. Values are NOT masked here —
-- masking is per-caller at query time, which is Sumun's job.
select
  customer_id,
  name,
  phone,
  rrn,
  email,
  region,
  cast(created_at as date) as created_at
from {{ ref('raw_customers') }}
