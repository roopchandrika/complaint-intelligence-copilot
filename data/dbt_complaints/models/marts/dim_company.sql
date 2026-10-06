-- One row per cleaned company. -1 = unknown company.
with companies as (
    select company,
           count(*)                      as raw_name_variants,
           string_agg(distinct legal_form, ', ') filter (where legal_form <> '') as legal_forms,
           bool_or(mapped_by_seed)       as mapped_by_seed
    from {{ ref('int_company_lookup') }}
    group by company
)
select -1 as company_key, 'Unknown' as company_name, 0 as raw_name_variants, null as legal_forms, false as mapped_by_seed
union all
select row_number() over (order by company), company, raw_name_variants, legal_forms, mapped_by_seed
from companies
