-- =====================================================================================
-- SILVER: cleaned, typed, deduplicated, standardized. Same grain as the source:
-- ONE ROW PER COMPLAINT. Every decision here is listed in ASSUMPTIONS.md (Day 7).
-- {{SEEDS}} is replaced by the seeds folder path when run_pipeline.py runs this file.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS silver;

-- Seeds: small, human-reviewed reference tables (version-controlled CSV files)
CREATE OR REPLACE TABLE silver.seed_product_map AS SELECT * FROM read_csv('{{SEEDS}}/product_map.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE silver.seed_issue_map   AS SELECT * FROM read_csv('{{SEEDS}}/issue_map.csv',   header = true, all_varchar = true);
CREATE OR REPLACE TABLE silver.seed_company_map AS SELECT * FROM read_csv('{{SEEDS}}/company_map.csv', header = true, all_varchar = true);
CREATE OR REPLACE TABLE silver.seed_state_ref   AS SELECT * FROM read_csv('{{SEEDS}}/state_ref.csv',   header = true, all_varchar = true);
CREATE OR REPLACE TABLE silver.seed_state_alias AS SELECT * FROM read_csv('{{SEEDS}}/state_alias.csv', header = true, all_varchar = true);

-- STEP 1. Company names: normalize the ~8,000 DISTINCT names once, not 18M rows.
--   a) clean text: upper case, drop apostrophes (IPAC'S -> IPACS), other punctuation -> space, drop a leading "THE"
--   b) base name: remove legal-form suffixes from the END only (never "CORP" in "CREDIT CORP SOLUTIONS");
--      remove a trailing HOLDINGS / GROUP only if 2+ words remain ("CL HOLDINGS" stays)
--   c) legal form: what was removed, standardized (CORPORATION -> CORP, NATIONAL ASSOCIATION -> NA, ...)
--   d) MERGE spellings with the same base only if they share ONE legal form (a spelling with no form may join).
--      Same base but different forms ("INDEPENDENT BANK CORP" vs "INDEPENDENT BANK GROUP INC") stay SEPARATE:
--      generic names with different legal forms are often different companies.
--   e) the curated seed map (a human decision) overrides everything.
CREATE OR REPLACE TABLE silver.company_lookup AS
WITH names AS (
    SELECT DISTINCT trim(company) AS company_raw
    FROM bronze.complaints_raw
    WHERE nullif(trim(company), '') IS NOT NULL
),
cleaned AS (
    SELECT company_raw,
           trim(regexp_replace(
               trim(regexp_replace(regexp_replace(regexp_replace(upper(company_raw), '[''`]', '', 'g'),
                                                  '[.,&"()/]', ' ', 'g'), '\s+', ' ', 'g')),
               '^THE ', '')) AS s
    FROM names
),
strong AS (
    SELECT company_raw, s, regexp_replace(regexp_replace(regexp_replace(s, ' (INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)$', ''), ' (INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)$', ''), ' (INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)$', '') AS b1
    FROM cleaned
),
weak AS (
    SELECT company_raw, s,
           CASE WHEN regexp_replace(b1, ' (HOLDINGS|HOLDING|GROUP)$', '') LIKE '% %'
                THEN regexp_replace(regexp_replace(regexp_replace(b1, ' (HOLDINGS|HOLDING|GROUP)$', ''), ' (INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)$', ''), ' (INC|INCORPORATED|LLC|L L C|LP|L P|LLP|L L P|CORP|CORPORATION|CO|COMPANY|N A|NA|NATIONAL ASSOCIATION|LTD|LIMITED|PLC)$', '')
                ELSE b1 END AS base
    FROM strong
),
forms AS (
    SELECT company_raw, base,
           -- the removed tail, standardized so that equivalent legal forms compare equal
           trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
               ' ' || trim(substr(s, length(base) + 1)) || ' ',
               ' INCORPORATED ', ' INC ', 'g'), ' CORPORATION ', ' CORP ', 'g'), ' COMPANY ', ' CO ', 'g'),
               ' NATIONAL ASSOCIATION ', ' NA ', 'g'), ' N A ', ' NA ', 'g'), ' L L C ', ' LLC ', 'g'),
               ' L P ', ' LP ', 'g'), ' (LIMITED|HOLDING) ', ' LTD ', 'g')) AS legal_form
    FROM weak
),
per_base AS (
    SELECT base, count(DISTINCT legal_form) FILTER (WHERE legal_form <> '') AS n_forms
    FROM forms
    GROUP BY base
)
SELECT f.company_raw,
       coalesce(m.company_canonical,
                CASE WHEN p.n_forms <= 1 THEN f.base
                     ELSE f.base || ' ' || f.legal_form END,     -- different legal forms: keep apart
                upper(f.company_raw))                              AS company,
       f.base                                                      AS company_norm,
       f.legal_form,
       m.company_canonical IS NOT NULL                             AS mapped_by_seed
FROM forms f
JOIN per_base p ON p.base = f.base
LEFT JOIN silver.seed_company_map m ON m.company_norm = f.base;

-- STEP 2. Typed and standardized rows (all source rows that have a valid ID and date)
CREATE OR REPLACE TABLE silver.complaints AS
WITH typed AS (
    SELECT
        TRY_CAST(trim(b.complaint_id) AS BIGINT)                          AS complaint_id,
        TRY_CAST(trim(b.date_received) AS DATE)                           AS date_received,
        TRY_CAST(trim(b.date_sent_to_company) AS DATE)                    AS date_sent_to_company,
        coalesce(nullif(trim(b.product), ''), 'Unknown')                  AS product,
        coalesce(nullif(trim(b.sub_product), ''), 'N/A')                  AS sub_product,
        coalesce(nullif(trim(b.issue), ''), 'Unknown')                    AS issue_raw,
        coalesce(nullif(trim(b.sub_issue), ''), 'N/A')                    AS sub_issue,
        nullif(trim(b.consumer_complaint_narrative), '')                  AS narrative,
        nullif(trim(b.company), '')                                       AS company_raw,
        upper(nullif(trim(b.state), ''))                                  AS state_raw,
        nullif(trim(b.zip_code), '')                                      AS zip_code,
        coalesce(nullif(trim(b.submitted_via), ''), 'Unknown')            AS submitted_via,
        coalesce(nullif(trim(b.company_response_to_consumer), ''), 'Unknown') AS company_response,
        CASE trim(b.timely_response)   WHEN 'Yes' THEN TRUE WHEN 'No' THEN FALSE END AS is_timely,
        CASE trim(b.consumer_disputed) WHEN 'Yes' THEN TRUE WHEN 'No' THEN FALSE END AS is_disputed,
        b._ingested_at,
        b._batch_id
    FROM bronze.complaints_raw b
),
enriched AS (
    SELECT t.*,
           coalesce(pm.product_group, t.product)                AS product_group,
           coalesce(im.issue_clean, t.issue_raw)                AS issue,
           cl.company                                           AS company,
           sr.state_code                                        AS state,
           coalesce(sr.region, CASE WHEN t.state_raw IS NULL THEN 'Unknown' ELSE 'Invalid code' END) AS region
    FROM typed t
    LEFT JOIN silver.seed_product_map pm ON pm.product = t.product
    LEFT JOIN silver.seed_issue_map   im ON im.issue_raw = t.issue_raw
    LEFT JOIN silver.company_lookup   cl ON cl.company_raw = t.company_raw
    LEFT JOIN silver.seed_state_alias sa ON sa.state_raw = t.state_raw          -- full names written instead of codes
    LEFT JOIN silver.seed_state_ref   sr ON sr.state_code = coalesce(sa.state_code, t.state_raw)
    WHERE t.complaint_id IS NOT NULL AND t.date_received IS NOT NULL
)
SELECT *,
       date_diff('day', date_received, date_sent_to_company)                                   AS days_to_send,
       (date_sent_to_company IS NOT NULL AND date_sent_to_company < date_received)             AS dq_sent_before_received,
       (state_raw IS NOT NULL AND state IS NULL)                                               AS dq_invalid_state,
       (date_received > CAST(_ingested_at AS DATE))                                            AS dq_future_date
FROM enriched
-- Deduplicate: one row per complaint_id. The most complete, most recent copy wins.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY complaint_id
    ORDER BY date_sent_to_company DESC NULLS LAST, _ingested_at DESC
) = 1;

-- STEP 3. Quarantine: rows that cannot be placed (no valid ID or no valid date), with the reason.
CREATE OR REPLACE TABLE silver.complaints_rejects AS
SELECT b.*,
       CASE WHEN TRY_CAST(trim(b.complaint_id) AS BIGINT) IS NULL THEN 'invalid complaint_id'
            ELSE 'invalid date_received' END AS reject_reason
FROM bronze.complaints_raw b
WHERE TRY_CAST(trim(b.complaint_id) AS BIGINT) IS NULL
   OR TRY_CAST(trim(b.date_received) AS DATE) IS NULL;
