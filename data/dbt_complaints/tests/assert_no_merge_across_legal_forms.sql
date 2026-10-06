-- Safety rule from the Day 6 review: the automatic rules must never merge spellings with
-- DIFFERENT legal forms (e.g. "INDEPENDENT BANK CORP" + "INDEPENDENT BANK GROUP INC").
-- Seed-mapped merges are human decisions and are allowed. Returns the offending companies.
select company,
       string_agg(distinct legal_form, ' | ')  as legal_forms,
       string_agg(company_raw, ' | ')          as raw_spellings
from {{ ref('int_company_lookup') }}
where not mapped_by_seed
group by company
having count(distinct legal_form) filter (where legal_form <> '') > 1
