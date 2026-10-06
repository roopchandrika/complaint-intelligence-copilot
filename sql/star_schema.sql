-- =====================================================================================
-- Day 5: Star schema for CFPB complaints (DuckDB)
--
-- Business process : consumer complaint intake and company response
-- GRAIN            : ONE ROW PER CFPB COMPLAINT (complaint_id) in fact_complaints
-- Dimensions       : dim_date (used twice: received + sent), dim_company, dim_product,
--                    dim_issue, dim_state, dim_response (junk dimension of small flags)
-- Measures         : complaint_count (always 1), days_to_send, is_timely, is_disputed, has_narrative
--
-- Keys: every dimension has a surrogate key (integer we assign). Key -1 = "Unknown",
-- so a fact row with a missing value still joins and still counts in totals.
--
-- Tables live in their own schema "star", next to the raw `complaints` table.
-- Primary keys are enforced on the small dimension tables. Foreign keys on the 18M-row fact
-- table are NOT enforced by the database (like Snowflake/BigQuery): they are checked by
-- sql/star_validate.sql instead, and on Day 7 by dbt "relationships" tests.
-- =====================================================================================

DROP SCHEMA IF EXISTS star CASCADE;
CREATE SCHEMA star;

-- One row per calendar day. Role-playing: the fact uses it as received date AND sent date.
CREATE TABLE star.dim_date (
    date_key      INTEGER PRIMARY KEY,      -- YYYYMMDD, e.g. 20250314; -1 = unknown
    full_date     DATE,
    year          SMALLINT,
    quarter       SMALLINT,
    month         SMALLINT,
    month_name    VARCHAR,
    year_month    VARCHAR,                  -- '2025-03'
    day_of_week   SMALLINT,                 -- ISO: 1 = Monday ... 7 = Sunday
    day_name      VARCHAR,
    is_weekend    BOOLEAN
);

-- One row per company name as received (cleaned further on Day 6)
CREATE TABLE star.dim_company (
    company_key         INTEGER PRIMARY KEY,
    company_name_raw    VARCHAR NOT NULL,
    company_name_clean  VARCHAR NOT NULL
);

-- One row per product + sub-product. product_group conforms old and new CFPB product names.
CREATE TABLE star.dim_product (
    product_key    INTEGER PRIMARY KEY,
    product        VARCHAR NOT NULL,        -- name exactly as in the source (old or new wording)
    sub_product    VARCHAR NOT NULL,        -- 'N/A' instead of NULL
    product_group  VARCHAR NOT NULL         -- stable name across CFPB renames, e.g. 'Credit reporting'
);

-- One row per issue + sub-issue
CREATE TABLE star.dim_issue (
    issue_key   INTEGER PRIMARY KEY,
    issue       VARCHAR NOT NULL,
    sub_issue   VARCHAR NOT NULL
);

-- One row per state / territory code
CREATE TABLE star.dim_state (
    state_key    INTEGER PRIMARY KEY,
    state_code   VARCHAR NOT NULL,
    state_name   VARCHAR NOT NULL,
    region       VARCHAR NOT NULL         -- US Census region, 'Territory / military', or 'Unknown'
);

-- Junk dimension: one row per combination of the small text flags
CREATE TABLE star.dim_response (
    response_key       INTEGER PRIMARY KEY,
    submitted_via      VARCHAR NOT NULL,
    company_response   VARCHAR NOT NULL,
    timely_response    VARCHAR NOT NULL,
    consumer_disputed  VARCHAR NOT NULL
);

-- FACT: one row per complaint. Foreign keys are documented here and checked by star_validate.sql.
CREATE TABLE star.fact_complaints (
    complaint_id       BIGINT,              -- degenerate dimension (an ID with no dimension table)
    date_received_key  INTEGER,             -- -> dim_date.date_key  (role: received)
    date_sent_key      INTEGER,             -- -> dim_date.date_key  (role: sent to company)
    company_key        INTEGER,             -- -> dim_company.company_key
    product_key        INTEGER,             -- -> dim_product.product_key
    issue_key          INTEGER,             -- -> dim_issue.issue_key
    state_key          INTEGER,             -- -> dim_state.state_key
    response_key       INTEGER,             -- -> dim_response.response_key
    complaint_count    SMALLINT,            -- always 1: additive, SUM it to count complaints
    days_to_send       INTEGER,             -- additive; AVG is meaningful
    is_timely          SMALLINT,            -- 1/0, NULL if unknown. SUM = number of timely responses
    is_disputed        SMALLINT,            -- 1/0, NULL if not collected
    has_narrative      SMALLINT             -- 1/0
);
