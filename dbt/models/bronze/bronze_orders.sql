-- Bronze: raw rows, append-only, no cleaning. One row per source record as received.
select
  order_id, customer_id, product_id, quantity, unit_price, status,
  cast(ordered_at as date) as ordered_at,
  current_timestamp as _ingested_at
from {{ ref('raw_orders') }}
{% if is_incremental() %}
where cast(ordered_at as date) > (select coalesce(max(ordered_at), date '1900-01-01') from {{ this }})
{% endif %}
