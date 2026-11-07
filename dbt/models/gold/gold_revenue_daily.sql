-- Gold: the one revenue number. Completed orders only; refunds and
-- cancellations excluded. This is the table `query_metric("revenue")` reads.
select
  o.ordered_at as date,
  c.region,
  p.category,
  sum(o.amount) as revenue,
  count(distinct o.order_id) as orders
from {{ ref('silver_orders') }} o
join {{ ref('silver_customers') }} c on c.customer_id = o.customer_id
join {{ ref('raw_products') }} p on p.product_id = o.product_id
where o.status = 'completed'
group by 1, 2, 3
