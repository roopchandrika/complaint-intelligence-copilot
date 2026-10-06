-- Every summary table adds back up to the cleaned table. Returns the tables that do not match.
with clean as (
    select count(*) as all_rows,
           count(*) filter (where company is not null)      as with_company,
           count(*) filter (where days_to_send is not null) as with_days
    from {{ ref('int_complaints') }}
),
checks as (
    select 'fct_complaints' as model, (select count(*) from {{ ref('fct_complaints') }}) as model_total, all_rows as expected from clean
    union all
    select 'agg_monthly_product', (select sum(complaints) from {{ ref('agg_monthly_product') }}), all_rows from clean
    union all
    select 'company_scorecard', (select sum(complaints) from {{ ref('company_scorecard') }}), with_company from clean
    union all
    select 'channel_forwarding_stats', (select sum(complaints) from {{ ref('channel_forwarding_stats') }}), with_days from clean
)
select * from checks where model_total <> expected
