-- DRILL 1. Order of evaluation: an alias defined in SELECT used in WHERE.
-- DuckDB allows this as a convenience; Postgres and SQL Server raise an error because WHERE runs before SELECT.
SELECT product AS p, count(*) AS n
FROM complaints
WHERE p = 'Mortgage'
GROUP BY p;

-- DRILL 1b. The portable version that works in every database.
SELECT product, count(*) AS n
FROM complaints
WHERE product = 'Mortgage'
GROUP BY product;

-- DRILL 2. ROW_NUMBER vs RANK vs DENSE_RANK on complaints per state (look for ties).
WITH by_state AS (
    SELECT state, count(*) AS n
    FROM complaints
    WHERE state IS NOT NULL
    GROUP BY state
)
SELECT state, n,
       ROW_NUMBER() OVER (ORDER BY n DESC) AS row_num,
       RANK()       OVER (ORDER BY n DESC) AS rnk,
       DENSE_RANK() OVER (ORDER BY n DESC) AS dense_rnk
FROM by_state
ORDER BY n DESC;

-- DRILL 3a. Reference table of US states (+ DC) for the LEFT JOIN trap.
CREATE OR REPLACE TABLE dim_state AS
SELECT unnest(['AL','AK','AZ','AR','CA','CO','CT','DE','DC','FL','GA','HI','ID','IL','IN','IA','KS',
               'KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ','NM','NY','NC',
               'ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT','VA','WA','WV','WI','WY']) AS state;

-- DRILL 3b. WRONG: the filter on the right table in WHERE removes states with no matching rows.
-- October 2026 has very few mortgage complaints, so most states have no match.
SELECT s.state, count(c.complaint_id) AS mortgage_complaints_oct_2026
FROM dim_state s
LEFT JOIN complaints c ON c.state = s.state
WHERE c.product = 'Mortgage' AND c.date_received >= DATE '2026-10-01'
GROUP BY s.state
ORDER BY mortgage_complaints_oct_2026
LIMIT 10;

-- DRILL 3c. RIGHT: the filter moves into ON, so every state is kept (with 0 when nothing matches).
SELECT s.state, count(c.complaint_id) AS mortgage_complaints_oct_2026
FROM dim_state s
LEFT JOIN complaints c
       ON c.state = s.state
      AND c.product = 'Mortgage'
      AND c.date_received >= DATE '2026-10-01'
GROUP BY s.state
ORDER BY mortgage_complaints_oct_2026
LIMIT 10;

-- DRILL 3d. Count how many states each version returns (compare the two numbers).
SELECT
  (SELECT count(DISTINCT s.state) FROM dim_state s LEFT JOIN complaints c ON c.state = s.state
   WHERE c.product = 'Mortgage' AND c.date_received >= DATE '2026-10-01') AS states_with_where_filter,
  (SELECT count(*) FROM dim_state) AS states_with_on_filter;

-- DRILL 4. NOT IN with a NULL returns nothing. Expected: no rows.
SELECT 'found' AS result WHERE 5 NOT IN (1, 2, NULL);

-- DRILL 4b. NOT EXISTS is NULL-safe. Expected: one row.
SELECT 'found' AS result
WHERE NOT EXISTS (SELECT 1 FROM (VALUES (1), (2), (NULL)) AS t(x) WHERE t.x = 5);

-- DRILL 5. Running count with ties: the default frame (RANGE) counts every complaint on the same day at once.
-- complaint_id is a tie-breaker so the ROWS frame counts 1, 2, 3 in a fixed order.
SELECT complaint_id, date_received,
       count(*) OVER (ORDER BY date_received)                                        AS default_range_frame,
       count(*) OVER (ORDER BY date_received, complaint_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_frame
FROM complaints
WHERE date_received = DATE '2025-03-03'
ORDER BY date_received, complaint_id
LIMIT 10;

-- DRILL 2b. Ranking with real ties: mortgage complaints per state in October 2026.
WITH by_state AS (
    SELECT state, count(*) AS n
    FROM complaints
    WHERE product = 'Credit card' AND date_received >= DATE '2026-10-01' AND state IS NOT NULL
    GROUP BY state
)
SELECT state, n,
       ROW_NUMBER() OVER (ORDER BY n DESC, state) AS row_num,
       RANK()       OVER (ORDER BY n DESC)        AS rnk,
       DENSE_RANK() OVER (ORDER BY n DESC)        AS dense_rnk
FROM by_state
ORDER BY n DESC, state;