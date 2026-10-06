-- Monthly volume and timeliness per product group. The last, incomplete month is flagged.
with last_day as (select max(date_received) as d from {{ ref('int_complaints') }} where not dq_future_date)
select cast(date_trunc('month', c.date_received) as date)                    as month,
       c.product_group,
       count(*)                                                              as complaints,
       count(*) filter (where c.is_timely = false)                           as late_responses,
       count(c.is_timely)                                                    as responses_known,
       round(100.0 * count(*) filter (where c.is_timely) / nullif(count(c.is_timely), 0), 2) as timely_pct,
       cast(date_trunc('month', c.date_received) as date)
           = cast(date_trunc('month', (select d from last_day)) as date)     as is_partial_month
from {{ ref('int_complaints') }} c
group by all
