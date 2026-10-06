# Phase 1 Summary — Data Engineering (Days 1–7)

**Project:** Complaint Intelligence Copilot
**Scenario:** Forward Deployed Engineer at a fictional retail bank, preparing complaint data for a secured RAG + agent copilot.
**Data:** CFPB Consumer Complaint Database, snapshot downloaded 2026-10-05 — 18,191,687 complaints, 2011-12-01 to 2026-10-05.
**Completed:** 2026-10-06

---

## Results at a glance

| Day | Topic | What I built | Headline result |
|---|---|---|---|
| 1 | FDE role and setup | Repo, client-scenario README, job-posting scorer with tests, 15 real FDE postings | 13 engineering, 1 mixed, 1 sales-disguised (Aircall, score −14) |
| 2 | Advanced SQL | DuckDB loader, 8 business queries, SQL drills | LEFT JOIN trap: filter in WHERE kept 3 states, filter in ON kept 51 |
| 3 | Query performance | Postgres in Docker, benchmark tool, 4 indexes, 1 materialized view, PERF.md | Lookup by ID 26,266 ms → 2.4 ms; an index made Q3 slower |
| 4 | Legacy databases | SQL Server in Docker, legacy schema, read-only login, parameterized client, 15 security tests, schema guide for the AI | Injected text matched all 50,000 cases as SQL text, 0 as a parameter |
| 5 | Data modeling | Star schema (1 fact, 6 dimensions), 6 validation checks, ER diagram | Averaging trap 74.22% vs real 99.55%; bad join 18.2M → 72.3M rows |
| 6 | Medallion layers | Bronze → Silver → Gold pipeline, seeds, data-quality report, merge review | Manual review found wrong company merges; safer rule: 8,144 spellings → 8,123 companies |
| 7 | dbt | dbt project: 13 models, 5 seeds, 62 data tests, 1 unit test, docs, ASSUMPTIONS.md | PASS=80, WARN=1, ERROR=0 in 102 s; matches Day 6 to the row (7,050 flagged) |

---

## Day by day

### Day 1 — The FDE role, filtering real jobs, setting up the capstone
**Built**
- Project repo with a README stating the client scenario.
- `jd/jd_scorer.py`: scores job postings with weighted keyword signals (engineering vs sales); 2 pytest tests.
- `jd/postings.csv`: 15 live FDE postings (Anthropic, Palantir, Flexport, Baseten, Netic, Aircall and others).

**Numbers**
- 13 of 15 roles scored as engineering, 1 mixed (Warner Music Group), 1 sales-disguised (Aircall: OTE, revenue targets, Sales org).
- CFPB file: 18,191,687 rows, every complaint ID unique.

**Learned**
- A keyword scorer ranks but does not understand: GWI scored "engineering" although its FDEs support account executives. A person still reads each posting.
- The CFPB file changes daily, so the snapshot date makes results reproducible.
- Windows setup: PowerShell `curl` is a different command; pytest needs `pythonpath = .`; SQL runs inside Python/DuckDB, not in the terminal.

### Day 2 — Advanced SQL: CTEs, joins, window functions
**Built**
- `data/load_duckdb.py`: loads 18M rows in 42 s, reading every column as text and typing it explicitly.
- `sql/analysis.sql`: 8 business queries (month-over-month change, top issues per company, running totals, moving averages, late-response rates, share of month, forwarding time).
- `sql/drills.sql`: evaluation order, ranking ties, LEFT JOIN trap, NOT IN with NULL, window frames.

**Numbers**
- All 8 queries under 0.5 s on 18M rows.
- LEFT JOIN trap: 3 states vs 51 states.
- Ranking ties (CA, IL, PA all at 6): ROW_NUMBER 1,2,3; RANK 1,1,1 then 4; DENSE_RANK 1,1,1 then 2.

**Learned**
- SQL runs in a different order than it is written: WHERE runs before SELECT.
- A filter on the right table of a LEFT JOIN belongs in ON. A bug can hide when every row happens to have a match.
- `NOT IN` returns nothing if the list contains NULL; `NOT EXISTS` is safe.
- Ties make the order inside a window random; add a tie-breaker column.
- Never trust automatic type guessing or documented column names: the real file had 15 columns, not 18.

**Data findings carried forward:** incomplete current month, renamed issues and products, 100%-late companies, 63 state values.

### Day 3 — Query performance: EXPLAIN ANALYZE, indexes, scans vs seeks
**Built**
- Postgres 16 in Docker, `data/load_postgres.py`, `perf.py` (median of 3 warm runs, saved plans, before/after report).
- 4 indexes (820 MB in total) and a materialized view; `PERF.md`.

**Numbers**

| Query | Before | After | Why |
|---|---|---|---|
| P1 one complaint by ID | 26,266 ms | 2.4 ms | unique index |
| Q2 month over month | 5,958 ms | 14 ms | materialized view |
| Q7 mortgage 3-month average | 27,451 ms | 94 ms | (product, date) index, Index Only Scan |
| P2 Wells Fargo top issues | 4,505 ms | 34 ms | (company, date) index |
| P3a `to_char(date) = '...'` | 3,654 ms | 2,424 ms | function on the column blocks the index |
| P3b `date = DATE '...'` | 1,107 ms | 2.9 ms | same index, written correctly (~800x faster than P3a) |
| Q3 top issues, top 10 companies | 12,073 ms | timed out | index made it worse |
| Q8 forwarding time by channel | 158,895 ms | 132,671 ms | needs pre-aggregation, not an index |

**Learned**
- An index helps only when a query needs a small part of the table; reading millions of rows through an index is slower than one full scan (Q3).
- Indexes cost memory and disk and can slow down queries that never use them (Q5).
- Column order in a composite index matters: "=" columns first, range columns last.
- Wrapping a column in a function stops index use.
- Environment issues were as hard as the SQL: a container name clash, a Windows Postgres on port 5432, Docker's 1 GB shared-memory limit, and forgotten Airflow containers skewing benchmarks.

### Day 4 — Legacy enterprise databases: SQL Server, drivers, safe access
**Built**
- SQL Server 2022 in Docker with a legacy-style schema (`TBL_CASE`, `TBL_CASE_STATUS`, `REF_STAT_CD`).
- `setup_legacy.py`: 50,000 cases and 146,384 status rows loaded in 247 s.
- `copilot_readonly` login (SELECT only); `legacy_client.py` with parameterized functions, allow-listed sorting, escaped LIKE patterns, row limits and query timeouts.
- `tests/test_readonly.py`: 15 tests, all passing.
- `data/legacy_schema.md`: plain-English schema guide for the AI agent; SOAP call with Zeep.

**Numbers**
- Current status: 38,941 closed, 7,930 under investigation, 2,355 escalated, 774 on legal hold.
- 7 kinds of writes and schema changes denied.

**Learned**
- Parameters keep values from becoming code. Identifiers cannot be parameterized, so use an allow-list.
- Least privilege: even an injected or wrong query cannot change data with a read-only login.
- DENY beats GRANT; a login is who you are, a user is what you may do in one database.
- Legacy schemas need a written guide (e.g. `CUR_FLG = 1` means current status) or an AI writes plausible but wrong SQL.
- The old built-in "SQL Server" ODBC driver cannot handle modern encryption; install ODBC Driver 18.
- An empty column still has a type: typed NULLs prevent "left(INTEGER)" errors.

### Day 5 — Data modeling: star schema, facts, dimensions, grain
**Built**
- Star schema in DuckDB: `fact_complaints` (grain: one row per complaint) with `dim_date` (role-playing), `dim_company`, `dim_product`, `dim_issue`, `dim_state`, `dim_response` (junk dimension).
- 6 validation checks; ER diagram (`docs/star_schema.png`).

**Numbers**
- Fact rows = source rows = 18,191,687; regions add up exactly; 64,601 unknown states.
- CFPB renamed products on 2017-04-24 and 2023-08-24; three credit-reporting names now roll up to one `product_group`.
- Credit reporting complaints: 307,538 (2021) → 4,810,298 (2025).
- Averaging trap: 74.22% (average of 3,968 company percentages) vs 99.55% (real).
- Fan-out: joining on a non-unique name turned 18,191,687 into 72,337,774.

**Learned**
- Decide the grain first; it makes totals checkable.
- Surrogate keys and an "Unknown" (-1) row keep every complaint in the totals.
- Never average percentages; add up the parts, then divide.
- One validation check is not enough: the missing-link check passed while every state was "Unknown".

### Day 6 — Medallion layers: Bronze → Silver → Gold
**Built**
- `run_pipeline.py`: Bronze (raw text + batch metadata) → Silver (typed, deduplicated, standardized, flagged) → Gold (4 business tables).
- Seeds: product groups, issue renames, company merges, state codes and aliases.
- `DQ_REPORT.md` with 5 reconciliation checks; `company_candidates.py` for fuzzy suggestions.

**Numbers**
- Bronze 18,191,687 = Silver 18,191,687 + 0 rejected + 0 duplicates; all checks PASS.
- Bronze 27 s, Silver 109 s, Gold 2 s; idempotent.
- 790,264 rows renamed to current issue wording, confirmed by data: old names stop 2017-04-21/22, new names start 2017-04-24.
- 7,050 complaints sent before received (flagged, kept); 0 invalid states after mapping 1,528 full territory names to UM.
- Company names: first rule merged 67 spellings; after manual review and the safer rule, 21 merges, all checked by hand. 8,144 spellings → 8,123 companies.
- Forwarding time by channel: 133 s (Postgres) → 446 ms (Silver) → 2 ms (Gold).

**Learned**
- Keep raw data untouched so cleaning can be rebuilt in about a minute (done three times).
- Never delete bad data silently: reject with a reason or flag it.
- Rules, then a reviewed list, then fuzzy suggestions; fuzzy matching only suggests.
- Generic names with different legal forms are often different companies ("Independent Bank Corp." MA vs "Independent Bank Group, Inc." TX).
- Checks prove counts, not correctness of every value: all checks passed while four cleaning mistakes and several wrong merges remained. Only reading the report found them.

### Day 7 — dbt + DuckDB: models, sources, tests, docs
**Built**
- `data/dbt_complaints`: staging → intermediate → marts (star schema + Gold tables).
- 5 seeds, 2 macros, 62 data tests (including 4 custom reconciliation/safety tests), 1 unit test for the company rules.
- dbt docs with lineage graph; `ASSUMPTIONS.md` with 21 documented decisions.

**Numbers**
- `dbt build` on 18,191,687 rows: 102 s, PASS=80, WARN=1, ERROR=0.
- The warning (7,050 negative forwarding times) matches Day 6 exactly.
- Broken seed run: PASS=26, ERROR=1, SKIP=54 — dbt stopped everything downstream.

**Learned**
- `ref()` builds the dependency graph; `source()` declares outside data.
- Views vs tables: staging as a view, the 18M-row cleaned table as a table.
- A test is a query that returns bad rows; `dbt build` skips everything downstream of a failure.
- Data tests check today's data; unit tests protect the logic.
- Edit seed files in a text editor, never in Excel.

---

## Repository deliverables

| Path | What it is |
|---|---|
| `README.md` | Client scenario |
| `LEARNINGS.md` | Daily log, Days 1–7 |
| `jd/` | Job-posting scorer, postings, tests |
| `data/load_duckdb.py`, `run_sql.py`, `sql/analysis.sql`, `sql/drills.sql` | Day 2 SQL |
| `docker-compose.yml`, `perf.py`, `sql/pg/`, `plans/`, `PERF.md` | Day 3 performance |
| `docker-compose.legacy.yml`, `data/legacy/`, `data/legacy_schema.md`, `tests/test_readonly.py` | Day 4 legacy access |
| `sql/star_*.sql`, `docs/star_schema.png`, `docs/star_schema.dbml` | Day 5 star schema |
| `data/medallion/`, `DQ_REPORT.md` | Day 6 pipeline |
| `data/dbt_complaints/`, `ASSUMPTIONS.md` | Day 7 dbt project |

---

## Interview stories (with real numbers)

1. **"Tell me about a performance problem you fixed."**
   A lookup by complaint ID read all 18M rows in 26 s; a unique index made it 2.4 ms. The same date question took 2,424 ms written with `to_char()` and 2.9 ms comparing the bare column, with the same index.
2. **"Tell me about an optimization that backfired."**
   After adding a (company, date) index, the "top issues for the top 10 companies" query went from 12 s to a 10-minute timeout. The planner fetched millions of rows through the index; one full scan was faster. Lesson: measure every query after adding an index.
3. **"How do you give an AI agent access to a bank's database safely?"**
   A read-only login, parameterized tool functions, an allow-list for identifiers, escaped LIKE patterns, row limits, timeouts, and a written schema guide — proven by 15 tests that try 7 kinds of writes.
4. **"Tell me about a data-quality mistake you caught."**
   Automatic company cleaning passed every check but merged "Credit Corp Solutions" into "Credit Solutions" and two different banks called "Independent Bank". Manual review found them; the fix was a safer rule (same legal form only) plus a unit test.
5. **"How do you know your numbers are right?"**
   Reconciliation (Bronze = Silver + rejects + duplicates; every Gold table adds back up), 62 dbt tests, a unit test, and two independent pipelines (Day 6 Python, Day 7 dbt) that agree on 7,050 flagged rows.
6. **"Explain a metric trap."**
   Averaging per-company timely percentages gave 74.22%; the real rate is 99.55%, because thousands of tiny companies counted as much as Equifax.

---

## Open items for later phases

- **Narratives missing:** my CSV has no complaint narrative column. RAG (Phase 3, Day 22) needs it — re-download the full CFPB file and confirm the header includes "Consumer complaint narrative".
- **Flagged companies:** 3 companies late on 99%+ of 500+ complaints — check before reporting.
- **7,050 complaints** with a sent date before the received date — investigate the source.
- **Legal-hold cases (LGL)** in the legacy system must be restricted to the compliance role (Day 27).
- **Q3 and Q5** in Postgres should read Gold tables rather than scanning 18M rows.
