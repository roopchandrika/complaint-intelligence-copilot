-- One row per raw company spelling -> the company it belongs to.
-- Rules (see ASSUMPTIONS.md):
--   1. clean text; 2. remove legal-form suffixes from the END only;
--   3. remove a trailing HOLDINGS / GROUP only if 2+ words remain;
--   4. merge spellings with the same base name only if they share ONE legal form
--      (a spelling with no legal form may join); different forms stay separate;
--   5. the curated seed company_map (a human decision) overrides everything.

with names as (
    select distinct company_raw
    from {{ ref('stg_complaints') }}
    where company_raw is not null
),

cleaned as (
    select company_raw, {{ clean_company_text('company_raw') }} as s
    from names
),

strong as (
    select company_raw, s, {{ strip_legal_suffixes('s') }} as b1
    from cleaned
),

weak as (
    select company_raw, s,
           case when regexp_replace(b1, ' (HOLDINGS|HOLDING|GROUP)$', '') like '% %'
                then {{ strip_legal_suffixes("regexp_replace(b1, ' (HOLDINGS|HOLDING|GROUP)$', '')", 2) }}
                else b1 end as base
    from strong
),

forms as (
    -- the removed tail, standardized so that equivalent legal forms compare equal
    select company_raw, base,
           trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
               ' ' || trim(substr(s, length(base) + 1)) || ' ',
               ' INCORPORATED ', ' INC ', 'g'), ' CORPORATION ', ' CORP ', 'g'), ' COMPANY ', ' CO ', 'g'),
               ' NATIONAL ASSOCIATION ', ' NA ', 'g'), ' N A ', ' NA ', 'g'), ' L L C ', ' LLC ', 'g'),
               ' L P ', ' LP ', 'g'), ' (LIMITED|HOLDING) ', ' LTD ', 'g')) as legal_form
    from weak
),

per_base as (
    select base, count(distinct legal_form) filter (where legal_form <> '') as n_forms
    from forms
    group by base
)

select
    f.company_raw,
    coalesce(
        m.company_canonical,
        case when p.n_forms <= 1 then nullif(f.base, '') else f.base || ' ' || f.legal_form end,
        upper(f.company_raw)
    )                                         as company,
    f.base                                    as company_base,
    f.legal_form,
    m.company_canonical is not null           as mapped_by_seed
from forms f
join per_base p on p.base = f.base
left join {{ ref('company_map') }} m on m.company_norm = f.base
