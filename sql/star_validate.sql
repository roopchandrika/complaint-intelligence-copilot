-- Day 5: prove the star schema is correct. Every check returns a "status" column: PASS or FAIL.

-- CHECK 1. Grain: the fact has exactly one row per complaint in the source (nothing lost, nothing duplicated).
SELECT *, CASE WHEN source_complaints = fact_rows AND fact_rows = fact_distinct_ids THEN 'PASS' ELSE 'FAIL' END AS status
FROM (SELECT (SELECT count(DISTINCT complaint_id) FROM complaints WHERE complaint_id IS NOT NULL) AS source_complaints,
             (SELECT count(*) FROM star.fact_complaints)                                         AS fact_rows,
             (SELECT count(DISTINCT complaint_id) FROM star.fact_complaints)                     AS fact_distinct_ids);

-- CHECK 2. Every foreign key in the fact finds its dimension row (no orphans).
SELECT 'date_received' AS fk, count(*) AS orphans FROM star.fact_complaints f
  LEFT JOIN star.dim_date d ON d.date_key = f.date_received_key WHERE d.date_key IS NULL
UNION ALL SELECT 'date_sent', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_date d ON d.date_key = f.date_sent_key WHERE d.date_key IS NULL
UNION ALL SELECT 'company', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_company d ON d.company_key = f.company_key WHERE d.company_key IS NULL
UNION ALL SELECT 'product', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_product d ON d.product_key = f.product_key WHERE d.product_key IS NULL
UNION ALL SELECT 'issue', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_issue d ON d.issue_key = f.issue_key WHERE d.issue_key IS NULL
UNION ALL SELECT 'state', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_state d ON d.state_key = f.state_key WHERE d.state_key IS NULL
UNION ALL SELECT 'response', count(*) FROM star.fact_complaints f
  LEFT JOIN star.dim_response d ON d.response_key = f.response_key WHERE d.response_key IS NULL;

-- CHECK 3. Dimension natural keys are unique (if not, joining the fact to them would multiply rows).
SELECT 'dim_company'  AS dim, count(*) - count(DISTINCT company_name_raw) AS duplicates FROM star.dim_company
UNION ALL SELECT 'dim_product',  count(*) - count(DISTINCT (product, sub_product)) FROM star.dim_product
UNION ALL SELECT 'dim_issue',    count(*) - count(DISTINCT (issue, sub_issue)) FROM star.dim_issue
UNION ALL SELECT 'dim_state',    count(*) - count(DISTINCT state_code) FROM star.dim_state
UNION ALL SELECT 'dim_response', count(*) - count(DISTINCT (submitted_via, company_response, timely_response, consumer_disputed)) FROM star.dim_response
UNION ALL SELECT 'dim_date',     count(*) - count(DISTINCT date_key) FROM star.dim_date;

-- CHECK 4. Totals reconcile: complaints per product group in the star = complaints in the raw table.
SELECT *, CASE WHEN star_total = raw_total THEN 'PASS' ELSE 'FAIL' END AS status
FROM (SELECT (SELECT sum(complaint_count) FROM star.fact_complaints)         AS star_total,
             (SELECT count(*) FROM complaints WHERE complaint_id IS NOT NULL) AS raw_total);

-- CHECK 5. How many fact rows point to an "Unknown" (-1) member. Small numbers are normal data quality;
-- a number close to ALL rows means a dimension failed to load (the orphan check alone would not catch it).
SELECT count(*) FILTER (WHERE company_key = -1)       AS unknown_company,
       count(*) FILTER (WHERE state_key = -1)         AS unknown_state,
       count(*) FILTER (WHERE date_sent_key = -1)     AS unknown_date_sent,
       count(*) FILTER (WHERE is_timely IS NULL)      AS unknown_timely
FROM star.fact_complaints;

-- CHECK 6. Size of each table.
SELECT 'fact_complaints' AS table_name, count(*) AS row_count FROM star.fact_complaints
UNION ALL SELECT 'dim_date', count(*) FROM star.dim_date
UNION ALL SELECT 'dim_company', count(*) FROM star.dim_company
UNION ALL SELECT 'dim_product', count(*) FROM star.dim_product
UNION ALL SELECT 'dim_issue', count(*) FROM star.dim_issue
UNION ALL SELECT 'dim_state', count(*) FROM star.dim_state
UNION ALL SELECT 'dim_response', count(*) FROM star.dim_response;
