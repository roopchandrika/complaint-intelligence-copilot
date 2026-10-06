-- Rows that cannot be placed (no valid complaint ID or no valid date), kept with the reason.
select
    *,
    case when complaint_id is null then 'invalid complaint_id'
         else 'invalid date_received' end as reject_reason
from {{ ref('stg_complaints') }}
where complaint_id is null or date_received is null
