-- How fast complaints are forwarded to companies, by submission channel.
select submitted_via,
       count(*)                                        as complaints,
       round(avg(days_to_send), 2)                     as avg_days,
       quantile_cont(days_to_send, 0.5)                as median_days,
       quantile_cont(days_to_send, 0.95)               as p95_days,
       count(*) filter (where dq_sent_before_received) as sent_before_received
from {{ ref('int_complaints') }}
where days_to_send is not null
group by submitted_via
