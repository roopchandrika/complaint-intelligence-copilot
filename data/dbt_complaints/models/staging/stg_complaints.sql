-- Staging: one row per Bronze row, typed and trimmed. No business rules, no filtering.
-- Materialized as a VIEW: it is only read by the intermediate models below.
{{ config(materialized='view') }}

select
    try_cast(trim(complaint_id) as bigint)                                    as complaint_id,
    trim(complaint_id)                                                        as complaint_id_raw,
    try_cast(trim(date_received) as date)                                     as date_received,
    try_cast(trim(date_sent_to_company) as date)                              as date_sent_to_company,
    coalesce(nullif(trim(product), ''), 'Unknown')                            as product,
    coalesce(nullif(trim(sub_product), ''), 'N/A')                            as sub_product,
    coalesce(nullif(trim(issue), ''), 'Unknown')                              as issue_raw,
    coalesce(nullif(trim(sub_issue), ''), 'N/A')                              as sub_issue,
    nullif(trim(consumer_complaint_narrative), '')                            as narrative,
    nullif(trim(company), '')                                                 as company_raw,
    upper(nullif(trim(state), ''))                                            as state_raw,
    nullif(trim(zip_code), '')                                                as zip_code,
    coalesce(nullif(trim(submitted_via), ''), 'Unknown')                      as submitted_via,
    coalesce(nullif(trim(company_response_to_consumer), ''), 'Unknown')       as company_response,
    case trim(timely_response)   when 'Yes' then true when 'No' then false end as is_timely,
    case trim(consumer_disputed) when 'Yes' then true when 'No' then false end as is_disputed,
    _ingested_at,
    _batch_id
from {{ source('bronze', 'complaints_raw') }}
