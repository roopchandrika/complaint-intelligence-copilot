-- Q1. Business question: How many complaints does each product receive per month?
SELECT product,
       date_trunc('month', date_received) AS month,
       count(*)                           AS complaints
FROM complaints
GROUP BY 1, 2
ORDER BY month DESC, complaints DESC;

-- Q2. Business question: Is each product getting better or worse month over month?
WITH monthly AS (
    SELECT product, date_trunc('month', date_received) AS month, count(*) AS n
    FROM complaints
    GROUP BY 1, 2
)
SELECT product, month, n,
       LAG(n) OVER w                                           AS prev_n,
       n - LAG(n) OVER w                                       AS mom_change,
       round(100.0 * (n - LAG(n) OVER w) / NULLIF(LAG(n) OVER w, 0), 1) AS mom_pct
FROM monthly
WINDOW w AS (PARTITION BY product ORDER BY month)
ORDER BY month DESC, n DESC;

-- Q3. Business question: What are the top 5 issues for each of the 10 most-complained-about companies?
WITH top_companies AS (
    SELECT company FROM complaints
    GROUP BY company ORDER BY count(*) DESC LIMIT 10
),
issue_counts AS (
    SELECT c.company, c.issue, count(*) AS n
    FROM complaints c
    JOIN top_companies t ON t.company = c.company
    GROUP BY 1, 2
),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY company ORDER BY n DESC) AS rnk
    FROM issue_counts
)
SELECT company, rnk, issue, n FROM ranked WHERE rnk <= 5 ORDER BY company, rnk;

-- Q4. Business question: What is the running total of complaints per product during 2025?
WITH daily AS (
    SELECT product, date_received AS d, count(*) AS n
    FROM complaints
    WHERE date_received >= DATE '2025-01-01' AND date_received < DATE '2026-01-01'
    GROUP BY 1, 2
)
SELECT product, d, n,
       sum(n) OVER (PARTITION BY product ORDER BY d
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM daily
ORDER BY product, d;

-- Q5. Business question: Which companies respond late most often (at least 500 complaints)?
SELECT company,
       count(*)                                        AS complaints,
       count(*) FILTER (WHERE timely_response = 'No')  AS late,
       round(100.0 * count(*) FILTER (WHERE timely_response = 'No') / count(*), 2) AS late_pct
FROM complaints
GROUP BY company
HAVING count(*) >= 500
ORDER BY late_pct DESC
LIMIT 20;

-- Q6. Business question: What share of each month's complaints does each product represent?
WITH monthly AS (
    SELECT date_trunc('month', date_received) AS month, product, count(*) AS n
    FROM complaints GROUP BY 1, 2
)
SELECT month, product, n,
       round(100.0 * n / sum(n) OVER (PARTITION BY month), 2) AS pct_of_month
FROM monthly
ORDER BY month DESC, pct_of_month DESC;

-- Q7. Business question: What is the 3-month moving average of mortgage complaints?
WITH monthly AS (
    SELECT date_trunc('month', date_received) AS month, count(*) AS n
    FROM complaints
    WHERE product = 'Mortgage'
    GROUP BY 1
)
SELECT month, n,
       round(avg(n) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS ma_3m
FROM monthly
ORDER BY month DESC;

-- Q8. Business question: How many days does the CFPB take to forward complaints, by channel?
SELECT submitted_via,
       count(*)                                                                         AS n,
       round(avg(date_sent_to_company - date_received), 2)                              AS avg_days,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY date_sent_to_company - date_received) AS median_days,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY date_sent_to_company - date_received) AS p95_days
FROM complaints
GROUP BY submitted_via
ORDER BY n DESC;

-- P1. Business question (API lookup): What is the full record for one complaint?
SELECT * FROM complaints WHERE complaint_id = 12278890;

-- P2. Business question (API lookup): What were Wells Fargo's top issues in 2025?
SELECT issue, count(*) AS n
FROM complaints
WHERE company = 'WELLS FARGO & COMPANY'
  AND date_received >= DATE '2025-01-01' AND date_received < DATE '2026-01-01'
GROUP BY issue
ORDER BY n DESC;

-- P3a. Business question: How many complaints arrived on 2025-03-03? (NOT sargable: function on the column)
SELECT count(*) FROM complaints WHERE to_char(date_received, 'YYYY-MM-DD') = '2025-03-03';

-- P3b. Business question: How many complaints arrived on 2025-03-03? (sargable: bare column vs a constant)
SELECT count(*) FROM complaints WHERE date_received = DATE '2025-03-03';

-- Q2-MV. Same question as Q2, answered from the pre-aggregated materialized view (exists only after fixes.sql)
WITH monthly AS (
    SELECT product, month, n FROM mv_monthly_product
)
SELECT product, month, n,
       LAG(n) OVER w                                           AS prev_n,
       n - LAG(n) OVER w                                       AS mom_change,
       round(100.0 * (n - LAG(n) OVER w) / NULLIF(LAG(n) OVER w, 0), 1) AS mom_pct
FROM monthly
WINDOW w AS (PARTITION BY product ORDER BY month)
ORDER BY month DESC, n DESC;