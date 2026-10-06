-- =====================================================================================
-- GOLD: business-ready tables built only from Silver. Small, fast, one question each.
-- These answer the questions that were slow on Day 3 (Q3, Q5, Q8) in milliseconds.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS gold;

-- 1. Monthly volume and timeliness per product group. The last (incomplete) month is flagged,
--    so trend charts and month-over-month numbers can exclude it (Day 2 finding).
CREATE OR REPLACE TABLE gold.monthly_product_stats AS
WITH last_day AS (SELECT max(date_received) AS d FROM silver.complaints WHERE NOT dq_future_date)
SELECT CAST(date_trunc('month', c.date_received) AS DATE)                    AS month,
       c.product_group,
       count(*)                                                              AS complaints,
       count(*) FILTER (WHERE c.is_timely = FALSE)                           AS late_responses,
       count(c.is_timely)                                                    AS responses_known,
       round(100.0 * count(*) FILTER (WHERE c.is_timely) / nullif(count(c.is_timely), 0), 2) AS timely_pct,
       CAST(date_trunc('month', c.date_received) AS DATE)
           = CAST(date_trunc('month', (SELECT d FROM last_day)) AS DATE)     AS is_partial_month
FROM silver.complaints c
GROUP BY ALL;

-- 2. Company scorecard (answers Day 3 Q5). Stores the parts (late, responses_known) so any
--    roll-up can recompute the percentage correctly (Day 5 averaging trap).
CREATE OR REPLACE TABLE gold.company_scorecard AS
SELECT company,
       count(*)                                                    AS complaints,
       count(DISTINCT company_raw)                                 AS raw_name_variants,
       count(DISTINCT product_group)                               AS product_groups,
       count(*) FILTER (WHERE is_timely = FALSE)                   AS late_responses,
       count(is_timely)                                            AS responses_known,
       round(100.0 * count(*) FILTER (WHERE is_timely = FALSE) / nullif(count(is_timely), 0), 2) AS late_pct,
       round(avg(days_to_send), 2)                                 AS avg_days_to_send,
       min(date_received)                                          AS first_complaint,
       max(date_received)                                          AS last_complaint,
       -- data-quality flag: a large company late on (almost) every complaint is more likely a
       -- recording quirk than reality. Check before reporting (Day 2 finding).
       (count(*) >= 500
        AND count(*) FILTER (WHERE is_timely = FALSE) >= 0.99 * count(is_timely)) AS dq_check_all_late
FROM silver.complaints
WHERE company IS NOT NULL
GROUP BY company;

-- 3. Top 10 issues per company, using cleaned issue names (answers Day 3 Q3).
CREATE OR REPLACE TABLE gold.company_top_issues AS
SELECT company, issue, count(*) AS complaints,
       DENSE_RANK() OVER (PARTITION BY company ORDER BY count(*) DESC) AS issue_rank
FROM silver.complaints
WHERE company IS NOT NULL
GROUP BY company, issue
QUALIFY issue_rank <= 10;

-- 4. Forwarding speed by channel (answers Day 3 Q8, which took 133 seconds in Postgres).
CREATE OR REPLACE TABLE gold.channel_forwarding_stats AS
SELECT submitted_via,
       count(*)                                    AS complaints,
       round(avg(days_to_send), 2)                 AS avg_days,
       quantile_cont(days_to_send, 0.5)            AS median_days,
       quantile_cont(days_to_send, 0.95)           AS p95_days,
       count(*) FILTER (WHERE dq_sent_before_received) AS sent_before_received
FROM silver.complaints
WHERE days_to_send IS NOT NULL
GROUP BY submitted_via;
