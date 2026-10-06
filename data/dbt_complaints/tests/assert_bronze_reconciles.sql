-- Every Bronze row is accounted for: Bronze = cleaned rows + rejected rows + duplicates removed.
-- Returns one row (= test fails) if the numbers do not add up.
with counts as (
    select
        (select count(*) from {{ source('bronze', 'complaints_raw') }})                    as bronze_rows,
        (select count(*) from {{ ref('stg_complaints_rejects') }})                          as rejected_rows,
        (select count(*) from {{ ref('int_complaints') }})                                  as clean_rows,
        (select count(distinct complaint_id) from {{ ref('stg_complaints') }}
          where complaint_id is not null and date_received is not null)                     as distinct_valid_ids
)
select *
from counts
where clean_rows <> distinct_valid_ids
   or bronze_rows < clean_rows + rejected_rows
