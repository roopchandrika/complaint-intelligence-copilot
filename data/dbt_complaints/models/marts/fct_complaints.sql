-- FACT. Grain: one row per CFPB complaint. Keys point to the dimensions; -1 = unknown.
select
    c.complaint_id,
    coalesce(cast(strftime(c.date_received, '%Y%m%d') as integer), -1)          as date_received_key,
    coalesce(cast(strftime(c.date_sent_to_company, '%Y%m%d') as integer), -1)   as date_sent_key,
    coalesce(co.company_key, -1)                                                 as company_key,
    p.product_key,
    coalesce(s.state_key, -1)                                                    as state_key,
    c.issue,
    c.submitted_via,
    c.company_response,
    1                                                                            as complaint_count,
    c.days_to_send,
    case when c.is_timely then 1 when not c.is_timely then 0 end                 as is_timely,
    case when c.is_disputed then 1 when not c.is_disputed then 0 end             as is_disputed,
    case when c.narrative is not null then 1 else 0 end                          as has_narrative,
    c.dq_sent_before_received,
    c.dq_invalid_state
from {{ ref('int_complaints') }} c
left join {{ ref('dim_company') }} co on co.company_name = c.company and co.company_key <> -1
join      {{ ref('dim_product') }} p  on p.product = c.product and p.sub_product = c.sub_product
left join {{ ref('dim_state') }}   s  on s.state_code = c.state and s.state_key <> -1
