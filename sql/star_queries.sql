-- BUSINESS 1. Complaints per product group per year, last 5 full years. One join per question, readable names.
SELECT d.year, p.product_group, sum(f.complaint_count) AS complaints
FROM star.fact_complaints f
JOIN star.dim_date d    ON d.date_key = f.date_received_key
JOIN star.dim_product p ON p.product_key = f.product_key
WHERE d.year BETWEEN 2021 AND 2025
GROUP BY d.year, p.product_group
ORDER BY d.year, complaints DESC;

-- BUSINESS 2. Old and new CFPB product names roll up into one stable product_group (Day 2 finding solved).
SELECT p.product_group, p.product, min(d.full_date) AS first_seen, max(d.full_date) AS last_seen,
       sum(f.complaint_count) AS complaints
FROM star.fact_complaints f
JOIN star.dim_product p ON p.product_key = f.product_key
JOIN star.dim_date d    ON d.date_key = f.date_received_key
GROUP BY p.product_group, p.product
ORDER BY p.product_group, first_seen;

-- BUSINESS 3. Timely-response rate by US Census region (territories and military shown separately).
SELECT s.region,
       sum(f.complaint_count)                                    AS complaints,
       round(100.0 * sum(f.is_timely) / count(f.is_timely), 2)   AS timely_pct
FROM star.fact_complaints f
JOIN star.dim_state s ON s.state_key = f.state_key
GROUP BY s.region
ORDER BY complaints DESC;

-- BUSINESS 4. Weekend vs weekday complaints, using attributes of the date dimension (no date functions needed).
SELECT d.is_weekend, d.day_name, sum(f.complaint_count) AS complaints
FROM star.fact_complaints f
JOIN star.dim_date d ON d.date_key = f.date_received_key
WHERE d.year = 2025
GROUP BY d.is_weekend, d.day_name, d.day_of_week
ORDER BY d.day_of_week;

-- DRILL 1. Role-playing dimension: dim_date joined TWICE, once as "received" and once as "sent".
SELECT r.year_month AS received_month, s.year_month AS sent_month, sum(f.complaint_count) AS complaints
FROM star.fact_complaints f
JOIN star.dim_date r ON r.date_key = f.date_received_key
JOIN star.dim_date s ON s.date_key = f.date_sent_key
WHERE r.year = 2025 AND r.month = 12
GROUP BY r.year_month, s.year_month
ORDER BY complaints DESC;

-- DRILL 2a. Additivity, the WRONG way: average each company's timely % (a company with 1 complaint
-- counts as much as one with 1 million).
WITH by_company AS (
    SELECT f.company_key, sum(f.is_timely) AS timely, count(f.is_timely) AS answered
    FROM star.fact_complaints f JOIN star.dim_date d ON d.date_key = f.date_received_key
    WHERE d.year = 2025
    GROUP BY f.company_key
)
SELECT count(*) AS companies, round(avg(100.0 * timely / answered), 2) AS avg_of_company_pct_WRONG
FROM by_company WHERE answered > 0;

-- DRILL 2b. Additivity, the RIGHT way: add up the parts (timely, answered) first, then divide once.
SELECT round(100.0 * sum(f.is_timely) / count(f.is_timely), 2) AS overall_timely_pct_RIGHT
FROM star.fact_complaints f JOIN star.dim_date d ON d.date_key = f.date_received_key
WHERE d.year = 2025;

-- DRILL 3a. Fan-out: a dimension whose join key is NOT unique multiplies fact rows. Build a bad lookup on purpose.
-- dim_product has one row per product + SUB-product, so each product name appears several times.
CREATE OR REPLACE TEMP TABLE bad_product_lookup AS
SELECT product, product_group FROM star.dim_product;

-- DRILL 3b. Joining on product alone: total complaints are inflated. Compare with the real total.
SELECT (SELECT sum(complaint_count) FROM star.fact_complaints) AS real_total,
       (SELECT sum(f.complaint_count)
        FROM star.fact_complaints f
        JOIN star.dim_product p ON p.product_key = f.product_key
        JOIN bad_product_lookup b ON b.product = p.product)   AS inflated_total;

-- DRILL 4a. Slowly changing dimension, Type 2: a company renamed on 2024-06-01 keeps both versions.
CREATE OR REPLACE TEMP TABLE dim_company_scd2 AS
SELECT * FROM (VALUES
    (1, 'ACME-001', 'ACME BANK',      DATE '2011-01-01', DATE '2024-06-01', FALSE),
    (2, 'ACME-001', 'ACME FINANCIAL', DATE '2024-06-01', NULL,              TRUE)
) AS t(company_key, company_id, company_name, valid_from, valid_to, is_current);

-- DRILL 4b. Each complaint joins to the version that was valid on the day it was received.
WITH complaints_demo AS (
    SELECT * FROM (VALUES (101, 'ACME-001', DATE '2023-03-10'),
                          (102, 'ACME-001', DATE '2024-05-31'),
                          (103, 'ACME-001', DATE '2024-06-01'),
                          (104, 'ACME-001', DATE '2025-01-15')) AS t(complaint_id, company_id, date_received)
)
SELECT c.complaint_id, c.date_received, d.company_name AS name_at_the_time, d.is_current
FROM complaints_demo c
JOIN dim_company_scd2 d
  ON d.company_id = c.company_id
 AND c.date_received >= d.valid_from
 AND c.date_received <  coalesce(d.valid_to, DATE '9999-12-31')
ORDER BY c.date_received;
