# Learnings

## Day 1 - FDE role and project setup (2026-10-05)

### What I built
- Created the project repo and a README that explains the client scenario.
- Wrote jd_scorer.py, which scores job postings to separate engineering roles from sales roles.
- Added 2 tests for the scorer; both pass.
- Collected 15 real FDE job postings in postings.csv.
- Downloaded the CFPB complaints data.

### Problems I hit and how I fixed them
- `curl -L` did not work in PowerShell. PowerShell's curl is a different command.
  Fix: used `curl.exe` and then switched to Git Bash.
- I pasted SQL directly into the terminal and got errors.
  Fix: SQL must be run through Python (DuckDB), not typed into the terminal.
- pytest could not find my `jd` folder.
  Fix: added a pytest.ini file with `pythonpath = .` and an empty jd/__init__.py file.
- A one-line `python -c "..."` command failed in PowerShell because of the quotes.
  Fix: put the code in a file (count_rows.py) and ran the file instead.

### Numbers
- Job postings: 13 of 15 scored as engineering roles, 1 as mixed (Warner Music),
  and 1 as a sales role (Aircall, score −14).
- CFPB data (downloaded 2026-10-05): 18,191,687 complaints.
- Every complaint ID is unique, so there are no duplicate rows.
- Dates run from 2011-12-01 to 2026-10-05.

### What I learned
- The scorer only counts keywords; it does not understand meaning. GWI's role was scored
  as engineering even though the engineers also help the sales team. The scorer is useful
  for sorting a list, but I still need to read each posting myself.
- The CFPB data is updated every day, so I write down the download date. This lets me
  (or anyone) reproduce my numbers later.
- If I download the data again, some complaints will appear twice. I will still build a
  step that removes duplicates (Day 6), even though there are none today.

## Day 2 - Advanced SQL: CTEs, joins, window functions (2026-10-05)

### What I built
- data/load_duckdb.py: loads the 18M-row CFPB CSV into a DuckDB table called `complaints`.
- run_sql.py: runs every query in a .sql file and prints results and timings.
- sql/analysis.sql: 8 queries, each answering one business question.
- sql/drills.sql: small exercises for joins, NULLs, rankings and window frames.

### Problems I hit and how I fixed them
- The loader stopped with "column not found". My CSV has 15 columns, not the 18 in the
  CFPB documentation: no complaint narrative, consumer consent or consumer disputed columns.
  Fix: the loader now reads the real header, matches names flexibly, and fills
  missing optional columns with NULL plus a warning.
- DuckDB's automatic type guessing turned "Timely response?" into true/false and named
  a column `subproduct`. Fix: read every column as text, then rename and cast each one myself.
- The LEFT JOIN drill first showed no difference (51 vs 51 states), because every state had
  mortgage complaints in 2025. The bug only appears when some rows have no match.
  Fix: used a rarer filter (October 2026) to make the difference visible.
- The ROWS running count gave random-looking numbers, because all 13,909 complaints
  on 2025-03-03 have the same date. Fix: added complaint_id as a tie-breaker in ORDER BY.
- The first ranking drill showed no ties between states, so all three ranking functions
  gave the same numbers. Fix: ranked a smaller set (credit card complaints in October 2026)
  where ties exist.

### Numbers
- Load time: 42 seconds for 18,191,687 rows.
- All 8 queries ran in under half a second. Slowest: Q8 (419 ms). Fastest: Q7 (23 ms).
- Mortgage complaints all time: 462,087.
- Credit reporting complaints in September 2026: 614,753.
- 96% of complaints (17.5M) were submitted on the web; median forwarding time is 0 days.
- LEFT JOIN drill: the WHERE version returned 3 states, the ON version 51.
  48 states were silently lost by putting the filter in the wrong place.

### What I learned
- SQL runs in a different order than it is written: WHERE runs before SELECT.
- In a LEFT JOIN, a filter on the right table belongs in ON, not WHERE.
  A bug can stay hidden when the data happens to have matches for every row, so test
  with cases that have no match.
- `NOT IN` returns nothing if the list contains a NULL. `NOT EXISTS` is safe.
- With ties (CA, IL, PA all at 6): ROW_NUMBER gave 1,2,3; RANK gave 1,1,1 then jumped to 4;
  DENSE_RANK gave 1,1,1 then 2. Use DENSE_RANK for "top N" so tied rows are kept.
- When values tie, the order inside a window is not fixed. Add a tie-breaker column.
- A running total needs `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`.
  The default frame counts every row with the same date together.
- Never trust automatic type guessing or documented column names. Check the real file.

### Data findings to handle later (Day 6)
- The current month is incomplete (5 days), so month-over-month shows a false 95–99% drop.
  Exclude the current month from trend queries.
- The same issue appears under old and new names (e.g. "Incorrect information on
  credit report" vs "Incorrect information on your report"). Needs a mapping.
- Two companies show 100% late responses (Federal Student Aid servicer, Mobiloans).
  Likely a data quirk; needs checking before reporting.
- "State" has 63 values, including territories and military codes, not just 50 states + DC.
- The narrative column is missing from my file; it is needed for RAG on Day 22.

## Day 3 - Query performance: EXPLAIN ANALYZE, indexes, scans vs seeks (2026-10-06)

### What I built
- docker-compose.yml: Postgres 16 in Docker.
- data/load_postgres.py: copies the 18M-row complaints table from DuckDB into Postgres.
- perf.py: times every query (median of 3 warm runs), saves each query plan,
  and builds a before/after table.
- sql/pg/perf_queries.sql: my 8 Day 2 queries in Postgres SQL, plus 4 lookup queries.
- sql/pg/fixes.sql: 4 indexes and 1 materialized view.
- sql/pg/drills.sql: exercises on plans, statistics, selectivity, index order,
  index-only scans, join types and sorting memory.
- PERF.md: before/after results with explanations.

### Problems I hit and how I fixed them
- `docker compose up` failed: a container named "pg" already existed from an earlier setup.
  Fix: removed the old container with `docker rm -f pg`.
- The loader failed with "password authentication failed for user postgres".
  Cause: a Postgres installed on Windows was already using port 5432, so my connection
  reached it instead of the Docker database.
  Fix: moved Docker Postgres to port 5433.
- VACUUM failed with "No space left on device". It was not the disk: the container
  has only 1 GB of shared memory, and VACUUM's parallel workers asked for 1 GB.
  Fix: lowered maintenance_work_mem to 256MB before running VACUUM.
- Two forgotten Airflow containers from an old project were running and set to restart
  automatically, taking memory during benchmarks.
  Fix: stopped them and turned off auto-restart (`docker update --restart=no`).
  Lesson: run `docker ps` before benchmarking.

### Numbers
- 18,191,687 rows in Postgres. The 4 indexes take 820 MB in total:
  complaint_id 390 MB, (company, date) 176 MB, (product, date) 132 MB, date 122 MB.
- Biggest wins (before → after):
  - P1 one complaint by ID: 26,266 ms → 2.4 ms (unique index).
  - Q2 month over month: 5,958 ms → 14 ms (materialized view, 431x faster).
  - P3b complaints on one date: 1,107 ms → 2.9 ms (date index).
  - Q7 mortgage 3-month average: 27,451 ms → 94 ms (product + date index, 292x faster).
  - P2 Wells Fargo top issues in 2025: 4,505 ms → 34 ms (company + date index).
- Same question, same index, different wording:
  - `to_char(date_received, ...) = '2025-03-03'` → 2,424 ms.
  - `date_received = DATE '2025-03-03'` → 2.9 ms (about 800x faster).
- Got worse after the fixes:
  - Q3 top issues for the top 10 companies: 12,073 ms → timed out after 10 minutes.
  - Q5 late responders: 2,697 ms → 30,904 ms, with the same plan.
- No real change: Q8 (159 s → 133 s), which calculates a median over all 18M rows.

### What I learned
- An index can make a query slower. For Q3 the planner used the (company, date) index to
  fetch millions of rows for the biggest companies. Jumping around the disk for millions
  of rows is far slower than reading the table once. Indexes are for finding a few rows.
- Every index uses memory. 820 MB of new indexes left less room to keep the table in
  memory, which likely made full-table queries like Q5 slower. An index can hurt queries
  that never use it.
- Postgres picks a plan using statistics. After loading data, run ANALYZE.
- An index helps only when a query needs a small part of the table. For 'Yes' in
  timely_response (most rows) Postgres ignored my index, and it was right to.
- Column order matters in a two-column index: (state, product) helps state, or
  state + product, but not product alone. Put "=" columns first, range columns last.
- Wrapping a column in a function stops the index from being used.
  Compare the bare column with a constant instead.
- If an index holds every column a query needs, Postgres never reads the table
  (Index Only Scan). That is why Q7 dropped to 94 ms.
- For whole-table totals, pre-calculating (materialized view) beats any index.
  Q3, Q5 and Q8 need pre-aggregated tables too: that is the Gold layer on Day 6.
- Always measure after adding an index. Check the queries you did not target as well,
  because they can get worse.
- Environment issues (container names, ports, shared memory, forgotten containers)
  caused as many problems as the SQL itself.

## Day 4 - Legacy enterprise databases: SQL Server, drivers, safe access (2026-10-06)

### What I built
- docker-compose.legacy.yml: SQL Server 2022 in Docker, playing the bank's old case system.
- 01_schema.sql: legacy-style tables (TBL_CASE, TBL_CASE_STATUS, REF_STAT_CD) with
  short cryptic column names, status codes and a "current status" flag.
- setup_legacy.py: loads 50,000 complaints from DuckDB as cases, plus a generated
  status history for each case.
- 02_readonly_login.sql: a login called copilot_readonly that can only SELECT.
- legacy_client.py: read-only functions the agent will use later (current status,
  case history, escalated cases, status counts). Every value is sent as a parameter.
- tests/test_readonly.py: 15 tests proving the login can read but never write.
- drills_legacy.py: SQL injection demo, permission table, schema discovery, T-SQL syntax.
- legacy_schema.md: plain-English guide to the schema for the AI (Day 17).
- soap_demo.py: called a SOAP web service and turned the XML answer into JSON.

### Problems I hit and how I fixed them
- setup_legacy.py failed: "No function matches left(INTEGER, ...)". My Day 2 loader filled
  missing columns with a plain NULL, which DuckDB stored as a number column, not text.
  Fix: cast columns to the expected type when reading, and fixed the loader to create
  missing columns as text. Lesson: an empty column still has a type, so set it explicitly.
- The script could not connect: my computer only had the very old built-in "SQL Server"
  ODBC driver, which cannot handle the encryption SQL Server 2022 uses.
  Fix: installed "ODBC Driver 18 for SQL Server" (winget was not available, so I used
  Microsoft's installer). A new terminal was needed before Python could see it.

### Numbers
- Setup: 50,000 cases and 146,384 status rows loaded in 247 seconds.
- Current status of the 50,000 cases: 38,941 closed, 7,930 under investigation,
  2,355 escalated, 774 on legal hold.
- Tests: 15 passed in 0.57 seconds (7 kinds of writes and schema changes denied).
- SQL injection drill: the same input matched all 50,000 cases when pasted into the SQL
  text, and 0 cases when sent as a parameter.

### What I learned
- SQL injection happens when user input is pasted into SQL text: the input becomes code.
  Parameters send the SQL and the values separately, so values can never become code.
- Parameters can only replace values, not table or column names. For a user-chosen sort
  column, map the choice to an allow-list of names I wrote myself.
- In a LIKE search, user input can contain % or _ wildcards. Escape them, or "%" matches
  every company.
- Least privilege: the copilot's login can only SELECT. Even if a query is wrong or
  injected, it cannot change or delete data. My tests prove this, not just the setup script.
- DENY always beats GRANT in SQL Server. I granted SELECT and denied everything else.
- A login is who you are on the server; a user is what you may do inside one database.
- Python reaches SQL Server through layers: pyodbc talks to the ODBC driver, which talks
  to the server. SQLAlchemy adds connection pooling, timeouts and parameter handling on top.
- Legacy schemas need a written guide. Without "CUR_FLG = 1 means current status", any
  count that joins the status history counts each case several times.
- I can discover an unknown schema using only system views: INFORMATION_SCHEMA for tables
  and columns, sys.foreign_keys for how tables join.
- SOAP services describe themselves in a WSDL file. Zeep reads it, builds the XML request,
  and turns the XML answer into Python objects I can save as JSON.

## Day 5 - Data modeling: star schema, facts, dimensions, grain (2026-10-06)

### What I built
- sql/star_schema.sql: a star schema in its own "star" schema in DuckDB.
  Grain: one row per CFPB complaint in fact_complaints.
- 6 dimensions: dim_date (used twice: received and sent), dim_company, dim_product,
  dim_issue, dim_state (with US Census regions), dim_response (small flags grouped together).
- sql/star_load.sql: fills the dimensions first, then the fact table. Every dimension has
  a surrogate key, and key -1 means "Unknown".
- sql/star_validate.sql: 6 checks that the star matches the raw data.
- sql/star_queries.sql: 4 business questions and 4 drills.
- docs/star_schema.png: the diagram.

### Problems I hit and how I fixed them
- My first version loaded every complaint with an "Unknown" state because the state
  lookup table failed to build. The missing-link check still passed (-1 exists in the
  dimension). Only counting the Unknown rows showed it.
  Lesson: validation needs more than one kind of check.
- PowerShell saved my query output with broken characters (ΓöîΓöÇ instead of lines).
  Fix: set the console to UTF-8 before using Out-File.

### Numbers
- Fact table: 18,191,687 rows, one per complaint. Totals match the raw table exactly.
- Complaints with an unknown state: 64,601 (0.36%).
- CFPB renamed its products on 2017-04-24 and 2023-08-24. Three different names for
  credit reporting now roll up into one product_group.
- Credit reporting complaints: 307,538 in 2021 → 4,810,298 in 2025 (about 15x).
- Weekdays get about 2-3 times more complaints than Sundays (Tuesday 984,456 vs Sunday 303,578).
- Complaints received in December 2025 were sent to companies as late as July 2026.
- Averaging trap: average of 3,968 company percentages = 74.22%,
  real overall timely rate = 99.55%.
- Fan-out: a join on a non-unique name turned 18,191,687 complaints into 72,337,774.

### What I learned
- Decide the grain first. "One row = one complaint" tells me which columns belong in the
  fact table and makes the totals checkable.
- Facts hold numbers I add up. Dimensions hold words I filter and group by.
- Surrogate keys (numbers I assign) keep the warehouse stable when source names change,
  and an "Unknown" row (-1) keeps complaints with missing values in the totals.
- One date table can play two roles (received and sent) by joining it twice.
- Never average percentages. Add up the parts (timely, answered) first, then divide once.
- A join on a column that is not unique multiplies rows silently. Check uniqueness of every
  dimension's key before joining.
- A star schema makes questions simple: each question is the fact table plus one join per
  description I need. That also makes it easier for an AI to write correct SQL later.
- A product_group column solved the CFPB renaming problem from Day 2 without changing
  the original values.
- Type 2 history keeps old versions of a row with valid-from and valid-to dates, so old
  complaints show the company name that was correct at the time.

## Day 6 - Medallion layers: Bronze → Silver → Gold (2026-10-06)

### What I built
- data/medallion/run_pipeline.py: one command builds all three layers in data/warehouse.duckdb.
- Bronze: the CSV exactly as received (all text) plus when, from which file and in which
  batch each row arrived. Re-loading the same file replaces its batch (no duplicates).
- Silver: typed, cleaned, one row per complaint. Bad rows go to a rejects table with a
  reason; duplicates are removed (newest copy wins); problems are flagged, not deleted.
- Gold: 4 small business tables (monthly product stats, company scorecard, top issues
  per company, forwarding speed by channel).
- Seeds: small reference lists I control (product groups, issue renames, company merges,
  state codes and aliases).
- dq_report.py: DQ_REPORT.md with 5 reconciliation checks, completeness, flags,
  company merges and timings.
- company_candidates.py: suggests look-alike company names for a person to review.

### Problems I hit and how I fixed them
- 1,528 complaints had the state written as "UNITED STATES MINOR OUTLYING ISLANDS"
  instead of the code UM, so they were flagged as invalid.
  Fix: a state alias list that maps full names to codes.
- Company cleaning removed too much: "CL Holdings LLC" became "CL".
  Fix: remove HOLDINGS / GROUP only when at least two words remain.
- "IPAC'S Inc." became "IPAC S" and "L.P." was not removed.
  Fix: delete apostrophes instead of replacing them with a space; add "L P" to the suffix list.
- Reviewing all company merges by hand found wrong ones:
  "Credit Corp Solutions Inc." was merged into "Credit Solutions" (the rule removed CORP
  from the middle of the name), and "Independent Bank Corp." (Massachusetts) was merged
  with "Independent Bank Group, Inc." (Texas), two different banks.
  Fix: remove suffixes only from the end of a name, and merge spellings only when they
  share the same legal form (Inc = Incorporated, Corp = Corporation, N.A. = National
  Association). Different legal forms stay separate unless I add them to company_map.csv.
- On test data, the fuzzy matcher scored "First National Bank of Omaha" and
  "...of Pennsylvania" as 88% similar. They are different banks.
  Lesson: fuzzy matching only suggests; a person decides.

### Numbers
- Bronze 18,191,687 = Silver 18,191,687 + 0 rejected + 0 duplicates. All 5 checks PASS.
- Run time: Bronze 27 s, Silver 109 s, Gold 2 s. Running it twice gives identical results.
- Rebuilding Silver and Gold after each fix took about 75 seconds, without reloading Bronze.
- Company names: 8,144 raw spellings became 8,123 companies. The first rule merged 67
  spellings; after manual review and the safer rule, 21 merges remain, all checked by hand.
- 790,264 rows renamed from old to current CFPB issue names. The data confirms the
  mapping: every old name stops on 2017-04-21/22 and its new name starts on 2017-04-24.
- Flags kept for review: 7,050 complaints sent before they were received;
  0 invalid state codes (1,528 before the alias fix).
- 3 companies late on 99%+ of 500+ complaints, flagged for checking
  (Federal Student Aid servicer: 7,544 complaints, 100% late).
- Day 3's slowest question (forwarding time by channel): 133 s in Postgres,
  446 ms from Silver, 2 ms from Gold.
- The narrative, consent and disputed columns are missing from my file (100% empty).

### What I learned
- Keep raw data untouched (Bronze). If a cleaning rule is wrong, I can rebuild Silver
  in about a minute without downloading the data again. I did that three times today.
- Never delete bad data silently. Rows that cannot be used go to a rejects table with
  a reason; suspicious rows get a flag column.
- Reconciliation proves nothing was lost: Bronze = Silver + rejects + duplicates removed,
  and every Gold table adds back up to Silver.
- Idempotent means running the pipeline twice gives the same result. Replacing tables
  instead of appending is what makes that true.
- Do expensive work on distinct values: cleaning about 8,000 company names once is far
  cheaper than cleaning 18 million rows.
- Rules, then a reviewed list, then fuzzy suggestions, in that order. In a bank, merging
  two different companies is worse than leaving two spellings of one company.
- Generic names (Credit Control, First Mortgage, Independent Bank) with different legal
  forms are often different companies. When unsure, keep them apart.
- Check mappings against the data: first-seen and last-seen dates proved the issue
  renames instead of me guessing.
- Gold tables answer business questions in milliseconds because the hard work happened once.
- Automatic checks all passed while some cleaning was wrong. Checks prove counts, not
  the correctness of every value. Only reading the report and the merge list found the
  mistakes.