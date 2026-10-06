-- Top 10 issues per company (cleaned issue names).
select company, issue, count(*) as complaints,
       dense_rank() over (partition by company order by count(*) desc) as issue_rank
from {{ ref('int_complaints') }}
where company is not null
group by company, issue
qualify issue_rank <= 10
