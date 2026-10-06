-- Only the most recent month may be flagged as partial. Returns any other flagged month.
select month
from {{ ref('agg_monthly_product') }}
where is_partial_month
  and month <> (select max(month) from {{ ref('agg_monthly_product') }})
group by month
