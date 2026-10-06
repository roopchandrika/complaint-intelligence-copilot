-- One row per state / territory code (from the seed), plus -1 = unknown or invalid.
select -1 as state_key, 'NA' as state_code, 'Unknown' as state_name, 'Unknown' as region
union all
select row_number() over (order by state_code), state_code, state_name, region
from {{ ref('state_ref') }}
