-- DRILL 1a. EXPLAIN shows the PLAN only (estimates). The query is not run.
EXPLAIN
SELECT count(*) FROM complaints WHERE state = 'WY';

-- DRILL 1b. EXPLAIN ANALYZE runs the query and adds ACTUAL rows and times. Compare "rows=" estimated vs actual.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM complaints WHERE state = 'WY';

-- DRILL 2. The statistics the planner uses for its estimates (collected by ANALYZE).
SELECT attname AS column_name, null_frac, n_distinct,
       (most_common_vals::text::text[])[1:5]   AS top_values,
       (most_common_freqs::text::real[])[1:5]  AS top_value_fractions
FROM pg_stats
WHERE tablename = 'complaints' AND attname IN ('state', 'timely_response', 'product', 'submitted_via');

-- DRILL 3a. Selectivity: create an index on a Yes/No column.
CREATE INDEX drill_idx_timely ON complaints (timely_response);

-- DRILL 3b. 'Yes' matches almost every row: the planner IGNORES the index (Seq Scan) - and it is right to.
-- The query also needs company, which is not in the index, so using the index would mean millions of table lookups.
EXPLAIN (ANALYZE)
SELECT count(DISTINCT company) FROM complaints WHERE timely_response = 'Yes';

-- DRILL 3c. 'No' matches few rows: now the index is worth using (Index Scan, or Bitmap Index Scan + Bitmap Heap Scan).
EXPLAIN (ANALYZE)
SELECT count(DISTINCT company) FROM complaints WHERE timely_response = 'No';

-- DRILL 3d. A partial index stores ONLY the rare rows. Compare its size with the full index.
CREATE INDEX drill_idx_late_company ON complaints (company) WHERE timely_response = 'No';

-- DRILL 3e. Index sizes: full index on every row vs partial index on late rows only.
SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes WHERE indexrelname LIKE 'drill_idx_%';

-- DRILL 3f. The partial index answers "late responses for one company" directly.
EXPLAIN (ANALYZE)
SELECT count(*) FROM complaints WHERE timely_response = 'No' AND company = 'EQUIFAX, INC.';

-- DRILL 3g. Clean up the drill indexes.
DROP INDEX drill_idx_timely;
DROP INDEX drill_idx_late_company;

-- DRILL 4a. Leftmost-prefix rule: a composite index on (state, product).
-- Drills 4b-4d also ask for max(date_received), which is NOT in the index, so the table must be read too.
CREATE INDEX drill_idx_state_product ON complaints (state, product);

-- DRILL 4b. Filter on the FIRST column: the index is used.
EXPLAIN (ANALYZE)
SELECT count(*), max(date_received) FROM complaints WHERE state = 'WY';

-- DRILL 4c. Filter on BOTH columns: the index is used even more precisely.
EXPLAIN (ANALYZE)
SELECT count(*), max(date_received) FROM complaints WHERE state = 'WY' AND product = 'Mortgage';

-- DRILL 4d. Filter on the SECOND column only: the index cannot be searched directly (expect a Seq Scan).
EXPLAIN (ANALYZE)
SELECT count(*), max(date_received) FROM complaints WHERE product = 'Mortgage';

-- DRILL 5. Index Only Scan: every column the query needs is in the index, so the table itself is never read.
-- Look for "Index Only Scan" and "Heap Fetches: 0".
EXPLAIN (ANALYZE, BUFFERS)
SELECT product, count(*) FROM complaints WHERE state = 'WY' GROUP BY product;

-- DRILL 5b. Clean up.
DROP INDEX drill_idx_state_product;

-- DRILL 6a. Join algorithms: a small lookup table of regions.
CREATE TEMP TABLE region_lookup AS
SELECT * FROM (VALUES ('TX','South'), ('FL','South'), ('GA','South'), ('CA','West'),
                      ('WA','West'), ('NY','Northeast'), ('PA','Northeast'), ('IL','Midwest'),
                      ('OH','Midwest'), ('WY','West')) AS t(state, region);

-- DRILL 6b. Small table joined to a big one: expect a Hash Join (hash the small side, scan the big side).
EXPLAIN (ANALYZE)
SELECT r.region, count(*)
FROM complaints c
JOIN region_lookup r ON r.state = c.state
GROUP BY r.region;

-- DRILL 7a. Memory and sorting: with very little work_mem, a big sort spills to disk.
SET work_mem = '4MB';

-- DRILL 7b. Look for "Sort Method: external merge  Disk: ...kB" (slow: the sort used temporary files).
EXPLAIN (ANALYZE)
SELECT complaint_id, company FROM complaints WHERE state = 'TX' ORDER BY company;

-- DRILL 7c. More memory for this session.
SET work_mem = '512MB';

-- DRILL 7d. Now look for "Sort Method: quicksort  Memory: ...kB" (the sort fits in memory).
EXPLAIN (ANALYZE)
SELECT complaint_id, company FROM complaints WHERE state = 'TX' ORDER BY company;

-- DRILL 7e. Back to the server default.
RESET work_mem;