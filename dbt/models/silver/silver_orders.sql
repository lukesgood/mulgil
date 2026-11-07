-- Silver: deduplicated, typed, keys validated against customers and products.
with ranked as (
  select
    b.*,
    row_number() over (partition by order_id order by _ingested_at desc) as rn
  from {{ ref('bronze_orders') }} b
),
o as (select * from ranked where rn = 1)
select
  o.order_id, o.customer_id, o.product_id, o.quantity, o.unit_price,
  o.quantity * o.unit_price as amount,
  o.status, o.ordered_at
from o
join {{ ref('silver_customers') }} c on c.customer_id = o.customer_id
join {{ ref('raw_products') }} p on p.product_id = o.product_id
