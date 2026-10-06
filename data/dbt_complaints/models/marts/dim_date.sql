-- One row per calendar day (role-playing: used as received date and sent date). -1 = unknown.
with days as (
    select cast(range as date) as d
    from range(date '2011-01-01', date '2028-01-01', interval 1 day)
)
select -1 as date_key, null::date as full_date, null::smallint as year, null::smallint as quarter,
       null::smallint as month, 'Unknown' as month_name, 'Unknown' as year_month,
       null::smallint as day_of_week, 'Unknown' as day_name, null::boolean as is_weekend
union all
select cast(strftime(d, '%Y%m%d') as integer), d, year(d), quarter(d), month(d), monthname(d),
       strftime(d, '%Y-%m'), isodow(d), dayname(d), isodow(d) in (6, 7)
from days
