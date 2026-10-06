-- Day 5: fill the star schema from the raw `complaints` table (run after star_schema.sql).
-- Order matters: dimensions first, then the fact table looks up their surrogate keys.

-- STEP 0. A typed, tidied view of the source. Every later step reads from this one place.
CREATE OR REPLACE VIEW star.v_source AS
SELECT
    CAST(complaint_id AS BIGINT)                                                  AS complaint_id,
    CAST(date_received AS DATE)                                                   AS date_received,
    CAST(date_sent_to_company AS DATE)                                            AS date_sent,
    coalesce(nullif(trim(CAST(product AS VARCHAR)), ''), 'Unknown')               AS product,
    coalesce(nullif(trim(CAST(sub_product AS VARCHAR)), ''), 'N/A')               AS sub_product,
    coalesce(nullif(trim(CAST(issue AS VARCHAR)), ''), 'Unknown')                 AS issue,
    coalesce(nullif(trim(CAST(sub_issue AS VARCHAR)), ''), 'N/A')                 AS sub_issue,
    nullif(trim(CAST(company AS VARCHAR)), '')                                    AS company,
    upper(nullif(trim(CAST(state AS VARCHAR)), ''))                               AS state,
    coalesce(nullif(trim(CAST(submitted_via AS VARCHAR)), ''), 'Unknown')         AS submitted_via,
    coalesce(nullif(trim(CAST(company_response_to_consumer AS VARCHAR)), ''), 'Unknown') AS company_response,
    coalesce(nullif(trim(CAST(timely_response AS VARCHAR)), ''), 'Unknown')       AS timely_response,
    coalesce(nullif(trim(CAST(consumer_disputed AS VARCHAR)), ''), 'Not collected') AS consumer_disputed,
    consumer_complaint_narrative IS NOT NULL                                      AS has_narrative
FROM complaints
WHERE complaint_id IS NOT NULL;

-- STEP 1. dim_date: every day from the first CFPB complaint to the end of next year, plus Unknown.
INSERT INTO star.dim_date VALUES (-1, NULL, NULL, NULL, NULL, 'Unknown', 'Unknown', NULL, 'Unknown', NULL);
INSERT INTO star.dim_date
SELECT CAST(strftime(d, '%Y%m%d') AS INTEGER), d,
       year(d), quarter(d), month(d), monthname(d), strftime(d, '%Y-%m'),
       isodow(d), dayname(d), isodow(d) IN (6, 7)
FROM (SELECT CAST(range AS DATE) AS d
      FROM range(DATE '2011-01-01', DATE '2028-01-01', INTERVAL 1 DAY));

-- STEP 2. dim_company: one row per raw name. Real cleaning happens on Day 6.
INSERT INTO star.dim_company VALUES (-1, 'Unknown', 'UNKNOWN');
INSERT INTO star.dim_company
SELECT ROW_NUMBER() OVER (ORDER BY company), company, upper(company)
FROM (SELECT DISTINCT company FROM star.v_source WHERE company IS NOT NULL);

-- STEP 3. dim_product: product + sub-product, with a product_group that survives CFPB renames.
INSERT INTO star.dim_product
SELECT ROW_NUMBER() OVER (ORDER BY product, sub_product), product, sub_product,
       CASE
           WHEN product ILIKE 'credit reporting%'                       THEN 'Credit reporting'
           WHEN product ILIKE 'debt collection%'                        THEN 'Debt collection'
           WHEN product ILIKE 'mortgage%'                               THEN 'Mortgage'
           WHEN product IN ('Bank account or service',
                            'Checking or savings account')              THEN 'Bank accounts'
           WHEN product ILIKE 'credit card%' OR product = 'Prepaid card' THEN 'Credit and prepaid cards'
           WHEN product ILIKE 'money transfer%' OR product = 'Virtual currency'
                                                                        THEN 'Money transfers'
           WHEN product ILIKE 'payday loan%' OR product = 'Consumer Loan' THEN 'Personal and payday loans'
           WHEN product = 'Vehicle loan or lease'                       THEN 'Vehicle loans'
           WHEN product = 'Student loan'                                THEN 'Student loans'
           WHEN product = 'Debt or credit management'                   THEN 'Debt or credit management'
           ELSE product
       END
FROM (SELECT DISTINCT product, sub_product FROM star.v_source);

-- STEP 4. dim_issue
INSERT INTO star.dim_issue
SELECT ROW_NUMBER() OVER (ORDER BY issue, sub_issue), issue, sub_issue
FROM (SELECT DISTINCT issue, sub_issue FROM star.v_source);

-- STEP 5. dim_state: reference list (names + US Census regions), then any other code found in the data.
CREATE OR REPLACE TEMP TABLE state_ref AS
SELECT * FROM (VALUES
 ('AL','Alabama','South'),('AK','Alaska','West'),('AZ','Arizona','West'),('AR','Arkansas','South'),
 ('CA','California','West'),('CO','Colorado','West'),('CT','Connecticut','Northeast'),('DE','Delaware','South'),
 ('DC','District of Columbia','South'),('FL','Florida','South'),('GA','Georgia','South'),('HI','Hawaii','West'),
 ('ID','Idaho','West'),('IL','Illinois','Midwest'),('IN','Indiana','Midwest'),('IA','Iowa','Midwest'),
 ('KS','Kansas','Midwest'),('KY','Kentucky','South'),('LA','Louisiana','South'),('ME','Maine','Northeast'),
 ('MD','Maryland','South'),('MA','Massachusetts','Northeast'),('MI','Michigan','Midwest'),('MN','Minnesota','Midwest'),
 ('MS','Mississippi','South'),('MO','Missouri','Midwest'),('MT','Montana','West'),('NE','Nebraska','Midwest'),
 ('NV','Nevada','West'),('NH','New Hampshire','Northeast'),('NJ','New Jersey','Northeast'),('NM','New Mexico','West'),
 ('NY','New York','Northeast'),('NC','North Carolina','South'),('ND','North Dakota','Midwest'),('OH','Ohio','Midwest'),
 ('OK','Oklahoma','South'),('OR','Oregon','West'),('PA','Pennsylvania','Northeast'),('RI','Rhode Island','Northeast'),
 ('SC','South Carolina','South'),('SD','South Dakota','Midwest'),('TN','Tennessee','South'),('TX','Texas','South'),
 ('UT','Utah','West'),('VT','Vermont','Northeast'),('VA','Virginia','South'),('WA','Washington','West'),
 ('WV','West Virginia','South'),('WI','Wisconsin','Midwest'),('WY','Wyoming','West'),
 ('PR','Puerto Rico','Territory / military'),('GU','Guam','Territory / military'),
 ('VI','U.S. Virgin Islands','Territory / military'),('AS','American Samoa','Territory / military'),
 ('MP','Northern Mariana Islands','Territory / military'),('FM','Micronesia','Territory / military'),
 ('MH','Marshall Islands','Territory / military'),('PW','Palau','Territory / military'),
 ('UM','U.S. Minor Outlying Islands','Territory / military'),
 ('AA','Armed Forces Americas','Territory / military'),('AE','Armed Forces Europe','Territory / military'),
 ('AP','Armed Forces Pacific','Territory / military')
) AS t(state_code, state_name, region);

INSERT INTO star.dim_state VALUES (-1, 'NA', 'Unknown', 'Unknown');
INSERT INTO star.dim_state
SELECT ROW_NUMBER() OVER (ORDER BY s.state), s.state,
       coalesce(r.state_name, 'Other code: ' || s.state),
       coalesce(r.region, 'Unknown')
FROM (SELECT DISTINCT state FROM star.v_source WHERE state IS NOT NULL) s
LEFT JOIN state_ref r ON r.state_code = s.state;

-- STEP 6. dim_response: junk dimension of the small flags
INSERT INTO star.dim_response
SELECT ROW_NUMBER() OVER (ORDER BY submitted_via, company_response, timely_response, consumer_disputed),
       submitted_via, company_response, timely_response, consumer_disputed
FROM (SELECT DISTINCT submitted_via, company_response, timely_response, consumer_disputed FROM star.v_source);

-- STEP 7. The fact table: look up every surrogate key; anything missing becomes -1 (Unknown).
INSERT INTO star.fact_complaints
SELECT
    s.complaint_id,
    coalesce(CAST(strftime(s.date_received, '%Y%m%d') AS INTEGER), -1),
    coalesce(CAST(strftime(s.date_sent, '%Y%m%d') AS INTEGER), -1),
    coalesce(co.company_key, -1),
    p.product_key,
    i.issue_key,
    coalesce(st.state_key, -1),
    r.response_key,
    1,
    date_diff('day', s.date_received, s.date_sent),
    CASE s.timely_response WHEN 'Yes' THEN 1 WHEN 'No' THEN 0 END,
    CASE s.consumer_disputed WHEN 'Yes' THEN 1 WHEN 'No' THEN 0 END,
    CASE WHEN s.has_narrative THEN 1 ELSE 0 END
FROM star.v_source s
LEFT JOIN star.dim_company  co ON co.company_name_raw = s.company AND co.company_key <> -1
JOIN      star.dim_product  p  ON p.product = s.product AND p.sub_product = s.sub_product
JOIN      star.dim_issue    i  ON i.issue = s.issue AND i.sub_issue = s.sub_issue
LEFT JOIN star.dim_state    st ON st.state_code = s.state AND st.state_key <> -1
JOIN      star.dim_response r  ON r.submitted_via = s.submitted_via
                              AND r.company_response = s.company_response
                              AND r.timely_response = s.timely_response
                              AND r.consumer_disputed = s.consumer_disputed;
