-- FIXES. Run once after the "before" benchmark:  python perf.py exec sql/pg/fixes.sql
-- Each index takes roughly 30-120 seconds on 18M rows.

-- Give index builds more memory for this session (faster sorting).
SET maintenance_work_mem = '1GB';

-- Fix 1 (P1): unique index for point lookups by complaint ID. Also enforces "one row per complaint".
CREATE UNIQUE INDEX IF NOT EXISTS idx_complaints_id ON complaints (complaint_id);

-- Fix 2 (P2): composite index. Equality column (company) first, range column (date) second.
CREATE INDEX IF NOT EXISTS idx_complaints_company_date ON complaints (company, date_received);

-- Fix 3 (Q7): composite index that covers the whole query, so Postgres can do an Index Only Scan.
CREATE INDEX IF NOT EXISTS idx_complaints_product_date ON complaints (product, date_received);

-- Fix 4 (P3b): index on the date alone. Only helps when the query compares the bare column.
CREATE INDEX IF NOT EXISTS idx_complaints_date ON complaints (date_received);

-- Fix 5 (Q1, Q2, Q6): pre-aggregate once. 18M rows become a few thousand.
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_product;
CREATE MATERIALIZED VIEW mv_monthly_product AS
SELECT product, date_trunc('month', date_received) AS month, count(*) AS n
FROM complaints
GROUP BY 1, 2;
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_product ON mv_monthly_product (product, month);

-- Refresh statistics and the visibility map (needed for Index Only Scans).
VACUUM ANALYZE complaints;
ANALYZE mv_monthly_product;

-- Show what was created and how big each index is.
SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;