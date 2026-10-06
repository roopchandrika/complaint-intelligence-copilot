-- The cleaned complaint table (Day 6 "Silver"). Grain: ONE ROW PER COMPLAINT_ID.
with valid as (
    select * from {{ ref('stg_complaints') }}
    where complaint_id is not null and date_received is not null
),

enriched as (
    select
        v.*,
        coalesce(pm.product_group, v.product)       as product_group,
        coalesce(im.issue_clean, v.issue_raw)       as issue,
        cl.company                                  as company,
        sr.state_code                               as state,
        coalesce(sr.region, case when v.state_raw is null then 'Unknown' else 'Invalid code' end) as region
    from valid v
    left join {{ ref('product_map') }}  pm on pm.product   = v.product
    left join {{ ref('issue_map') }}    im on im.issue_raw = v.issue_raw
    left join {{ ref('int_company_lookup') }} cl on cl.company_raw = v.company_raw
    left join {{ ref('state_alias') }}  sa on sa.state_raw = v.state_raw      -- full names written instead of codes
    left join {{ ref('state_ref') }}    sr on sr.state_code = coalesce(sa.state_code, v.state_raw)
)

select
    *,
    date_diff('day', date_received, date_sent_to_company)                           as days_to_send,
    (date_sent_to_company is not null and date_sent_to_company < date_received)     as dq_sent_before_received,
    (state_raw is not null and state is null)                                       as dq_invalid_state,
    (date_received > cast(_ingested_at as date))                                    as dq_future_date
from enriched
-- one row per complaint: the most complete, most recent copy wins
qualify row_number() over (
    partition by complaint_id
    order by date_sent_to_company desc nulls last, _ingested_at desc
) = 1
