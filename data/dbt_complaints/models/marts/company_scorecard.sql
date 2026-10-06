-- One row per company. Stores the parts (late, responses_known) so roll-ups recompute % correctly.
select company,
       count(*)                                                    as complaints,
       count(distinct company_raw)                                 as raw_name_variants,
       count(distinct product_group)                               as product_groups,
       count(*) filter (where is_timely = false)                   as late_responses,
       count(is_timely)                                            as responses_known,
       round(100.0 * count(*) filter (where is_timely = false) / nullif(count(is_timely), 0), 2) as late_pct,
       round(avg(days_to_send), 2)                                 as avg_days_to_send,
       min(date_received)                                          as first_complaint,
       max(date_received)                                          as last_complaint,
       (count(*) >= 500
        and count(*) filter (where is_timely = false) >= 0.99 * count(is_timely)) as dq_check_all_late
from {{ ref('int_complaints') }}
where company is not null
group by company
