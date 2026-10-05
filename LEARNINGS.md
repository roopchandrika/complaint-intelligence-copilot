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