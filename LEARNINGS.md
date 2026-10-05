# Learnings

## Day 1 — FDE role and project setup (2026-10-05)

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

## Day 2 — Advanced SQL: CTEs, joins, window functions (2026-10-05)

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