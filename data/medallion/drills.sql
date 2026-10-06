-- DRILL 1. Profile Bronze before cleaning anything: type, distinct values, nulls, min/max for every column.
SUMMARIZE bronze.complaints_raw;

-- DRILL 2. Lineage: one Silver row next to the exact Bronze row it came from (what did cleaning change?).
SELECT 'bronze' AS layer, b.complaint_id, b.company, b.issue, b.state, b.timely_response, b.date_received
FROM bronze.complaints_raw b
WHERE b.complaint_id = (SELECT CAST(min(complaint_id) AS VARCHAR) FROM silver.complaints WHERE issue <> issue_raw)
UNION ALL
SELECT 'silver', CAST(s.complaint_id AS VARCHAR), s.company, s.issue, s.state, CAST(s.is_timely AS VARCHAR), CAST(s.date_received AS VARCHAR)
FROM silver.complaints s
WHERE s.complaint_id = (SELECT min(complaint_id) FROM silver.complaints WHERE issue <> issue_raw);

-- DRILL 3. Company cleaning: every raw spelling that became one company, for the 15 biggest companies.
SELECT l.company, count(*) AS raw_spellings, string_agg(l.company_raw, ' | ' ORDER BY l.company_raw) AS spellings
FROM silver.company_lookup l
WHERE l.company IN (SELECT company FROM gold.company_scorecard ORDER BY complaints DESC LIMIT 15)
GROUP BY l.company
ORDER BY raw_spellings DESC;

-- DRILL 4. Evidence for the issue_map: an old name should stop around the date the new name starts.
SELECT issue_raw, issue AS mapped_to, min(date_received) AS first_seen, max(date_received) AS last_seen, count(*) AS rows
FROM silver.complaints
WHERE issue_raw IN (SELECT issue_raw FROM silver.seed_issue_map)
   OR issue    IN (SELECT issue_clean FROM silver.seed_issue_map)
GROUP BY issue_raw, issue
ORDER BY mapped_to, first_seen;

-- DRILL 5. Duplicates: complaint IDs that appeared more than once in Bronze, and which copy Silver kept.
WITH dup_ids AS (
    SELECT complaint_id FROM bronze.complaints_raw
    WHERE TRY_CAST(trim(complaint_id) AS BIGINT) IS NOT NULL
    GROUP BY complaint_id HAVING count(*) > 1
    LIMIT 5
)
SELECT b.complaint_id, b.date_sent_to_company AS bronze_date_sent,
       s.date_sent_to_company AS silver_kept_date_sent
FROM bronze.complaints_raw b
JOIN dup_ids d USING (complaint_id)
LEFT JOIN silver.complaints s ON s.complaint_id = TRY_CAST(trim(b.complaint_id) AS BIGINT)
ORDER BY b.complaint_id, b.date_sent_to_company;

-- DRILL 6. The quarantine: rejected rows keep every original value plus the reason.
SELECT reject_reason, complaint_id, date_received, company, product
FROM silver.complaints_rejects
LIMIT 10;

-- DRILL 7. The incomplete current month is flagged, so trend charts can leave it out.
SELECT month, sum(complaints) AS complaints, bool_or(is_partial_month) AS is_partial_month
FROM gold.monthly_product_stats
GROUP BY month
ORDER BY month DESC
LIMIT 4;

-- DRILL 8a. Day 3's slow question Q5 (late responders), answered from SILVER (scans every row).
SELECT company, count(*) AS complaints,
       round(100.0 * count(*) FILTER (WHERE is_timely = FALSE) / count(is_timely), 2) AS late_pct
FROM silver.complaints
WHERE company IS NOT NULL
GROUP BY company HAVING count(*) >= 500
ORDER BY late_pct DESC LIMIT 10;

-- DRILL 8b. The same question answered from GOLD (pre-aggregated). Compare the two timings.
SELECT company, complaints, late_pct, dq_check_all_late
FROM gold.company_scorecard
WHERE complaints >= 500
ORDER BY late_pct DESC LIMIT 10;

-- DRILL 9a. Day 3's slowest question Q8 (133 s in Postgres) from SILVER.
SELECT submitted_via, count(*) AS complaints,
       quantile_cont(days_to_send, 0.5) AS median_days, quantile_cont(days_to_send, 0.95) AS p95_days
FROM silver.complaints WHERE days_to_send IS NOT NULL
GROUP BY submitted_via ORDER BY complaints DESC;

-- DRILL 9b. The same question from GOLD.
SELECT submitted_via, complaints, median_days, p95_days FROM gold.channel_forwarding_stats ORDER BY complaints DESC;

-- DRILL 10. Data-quality flags are kept as columns, not deleted: how many rows carry each flag?
SELECT count(*) FILTER (WHERE dq_sent_before_received) AS sent_before_received,
       count(*) FILTER (WHERE dq_invalid_state)        AS invalid_state,
       count(*) FILTER (WHERE dq_future_date)          AS future_date,
       count(*)                                        AS all_rows
FROM silver.complaints;

-- DRILL 11. Review EVERY merge: companies built from more than one raw spelling. A wrong merge
-- (two different companies under one name) is worse than a missed one, so read this list.
SELECT g.company, g.complaints, g.raw_name_variants,
       string_agg(l.company_raw, ' | ' ORDER BY l.company_raw) AS raw_spellings
FROM gold.company_scorecard g
JOIN silver.company_lookup l ON l.company = g.company
WHERE g.raw_name_variants > 1
GROUP BY g.company, g.complaints, g.raw_name_variants
ORDER BY g.complaints DESC;
