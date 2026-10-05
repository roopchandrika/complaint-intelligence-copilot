-- Q1. Business question: How many complaints does each product receive per month?
SELECT product,
       date_trunc('month', date_received) AS month,
       count(*)                           AS complaints
FROM complaints
GROUP BY product, month
ORDER BY month DESC, complaints DESC;

-- Q2. Business question: Is each product getting better or worse month over month?
WITH monthly AS (
    SELECT product,
           date_trunc('month', date_received) AS month,
           count(*)                           AS n
    FROM complaints
    GROUP BY product, month
)
SELECT product, month, n,
       LAG(n) OVER (PARTITION BY product ORDER BY month)      AS prev_n,
       n - LAG(n) OVER (PARTITION BY product ORDER BY month)  AS mom_change,
       round(100.0 * (n - LAG(n) OVER (PARTITION BY product ORDER BY month))
             / NULLIF(LAG(n) OVER (PARTITION BY product ORDER BY month), 0), 1) AS mom_pct
FROM monthly
ORDER BY month DESC, n DESC;

-- Q3. Business question: What are the top 5 issues for each of the 10 most-complained-about companies?
WITH top_companies AS (
    SELECT company
    FROM complaints
    GROUP BY company
    ORDER BY count(*) DESC
    LIMIT 10
),
issue_counts AS (
    SELECT c.company, c.issue, count(*) AS n
    FROM complaints c
    JOIN top_companies t ON t.company = c.company
    GROUP BY c.company, c.issue
),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY company ORDER BY n DESC) AS rnk
    FROM issue_counts
)
SELECT company, rnk, issue, n
FROM ranked
WHERE rnk <= 5
ORDER BY company, rnk;

-- Q4. Business question: What is the running total of complaints per product during 2025?
WITH daily AS (
    SELECT product, date_received AS d, count(*) AS n
    FROM complaints
    WHERE date_received >= DATE '2025-01-01' AND date_received < DATE '2026-01-01'
    GROUP BY product, d
)
SELECT product, d, n,
       sum(n) OVER (PARTITION BY product ORDER BY d
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM daily
ORDER BY product, d;

-- Q5. Business question: Which companies respond late most often (companies with at least 500 complaints)?
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
    FROM complaints
    GROUP BY month, product
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
    GROUP BY month
)
SELECT month, n,
       round(avg(n) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS ma_3m
FROM monthly
ORDER BY month DESC;

-- Q8. Business question: How many days does the CFPB take to forward complaints, by submission channel?
SELECT submitted_via,
       count(*)                                                               AS n,
       round(avg(date_diff('day', date_received, date_sent_to_company)), 2)   AS avg_days,
       quantile_cont(date_diff('day', date_received, date_sent_to_company), 0.5)  AS median_days,
       quantile_cont(date_diff('day', date_received, date_sent_to_company), 0.95) AS p95_days
FROM complaints
GROUP BY submitted_via
ORDER BY n DESC;