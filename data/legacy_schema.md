# Legacy case system — schema guide

**System:** the bank's case-management database. Microsoft SQL Server 2022, database `BankLegacy`, schema `dbo`.
**Dialect:** T-SQL. Use `TOP n` (not `LIMIT`), `DATEFROMPARTS` / `DATEDIFF`, `CONCAT` or `+` for text.
**Access:** login `copilot_readonly` can only `SELECT`. Writes, schema changes and procedures are denied.
**Rules for generated SQL:** always include `TOP` (max 500 rows); always filter `CUR_FLG = 1` for "current" questions; use only the tables below.

## How the tables fit together

```text
REF_STAT_CD (5 rows)          TBL_CASE (50,000 rows)            TBL_CASE_STATUS (~150,000 rows)
  STAT_CD  <────────────────────────────────────────────────────  STAT_CD
                                CASE_ID  <──────────────────────  CASE_ID
                                CMPL_ID  (= CFPB complaint_id in the analytics warehouse)
```

- `TBL_CASE.CASE_ID = TBL_CASE_STATUS.CASE_ID` (one case has many status rows)
- `TBL_CASE_STATUS.STAT_CD = REF_STAT_CD.STAT_CD` (code → description)
- `TBL_CASE.CMPL_ID` joins to `complaint_id` in the DuckDB/Postgres complaints warehouse

## dbo.TBL_CASE — one row per customer complaint case

| Column | Type | Meaning |
|---|---|---|
| CASE_ID | int, primary key | Internal case number. Use it only for joins. |
| CMPL_ID | bigint, unique | CFPB complaint ID. This is the ID users and other systems mention. |
| PRD_DESC | nvarchar(100) | Financial product, e.g. `Mortgage`, `Credit card`, `Credit reporting or other personal consumer reports`. |
| ISS_DESC | nvarchar(255) | What went wrong, e.g. `Incorrect information on your report`. Old and new CFPB wording both appear. |
| CO_NM | nvarchar(255) | Company name exactly as received, e.g. `EQUIFAX, INC.`, `WELLS FARGO & COMPANY`. Not cleaned: use `LIKE 'EQUIFAX%'`, not `=`. |
| ST_CD | char(2) | Customer's state or territory code, e.g. `TX`. Includes territories and military codes (`PR`, `GU`, `AA`). Can be NULL. |
| RCV_DT | date | Date the complaint was received. |
| CHNL | varchar(30) | How it was submitted: `Web`, `Referral`, `Phone`, `Postal mail`, `Fax`, `Email`. |
| NARR_TXT | nvarchar(4000) | Customer's own description, truncated to 4,000 characters. **NULL in this extract** (the source file had no narrative column). |

## dbo.TBL_CASE_STATUS — one row per status change (history)

| Column | Type | Meaning |
|---|---|---|
| STAT_ID | int, primary key | Row id. |
| CASE_ID | int | The case this status belongs to. |
| STAT_CD | char(3) | Status code. Meaning is in `REF_STAT_CD`. |
| ASGN_TEAM | varchar(50) | Team that owned the case at that moment: `Tier1`, `Tier2`, `Complaints-Exec`, `Legal`. |
| UPD_TS | datetime2(0) | When the status changed. |
| CUR_FLG | bit | **1 = this is the case's current status.** Exactly one row per case has `CUR_FLG = 1`. |

## dbo.REF_STAT_CD — status codes

| STAT_CD | STAT_DESC | Notes |
|---|---|---|
| OPN | Open | First status of every case. |
| INV | Under investigation | Second status of every case. |
| ESC | Escalated | About 12% of cases are escalated at some point. Owner: Complaints-Exec. |
| LGL | Legal hold | About a quarter of escalated cases. **Restricted:** only the compliance role may see case details (Day 27). |
| CLS | Closed | Final status. About 80% of cases are currently closed. |

Every case follows `OPN → INV → (ESC → (LGL)) → (CLS)`.

## Gotchas

1. **Double counting.** A case has 2–5 status rows. Any count of cases that joins `TBL_CASE_STATUS` without `CUR_FLG = 1` will be too high.
2. **"Was escalated" vs "is escalated".** Use `CUR_FLG = 1 AND STAT_CD = 'ESC'` for "is escalated now". Use `STAT_CD = 'ESC'` without the flag, plus `COUNT(DISTINCT CASE_ID)`, for "was ever escalated".
3. **Company names are not normalized.** Match with `LIKE 'NAME%'`. Never assume one spelling.
4. **The narrative column is empty in this extract.** Do not use it to answer questions.
5. **Dates:** `RCV_DT` is a `date`. `UPD_TS` is a `datetime2`. Compare them with `CAST(RCV_DT AS datetime2)`.

## Example questions and correct SQL

**How many Equifax cases are escalated right now?**
```sql
SELECT COUNT(*) AS escalated_now
FROM dbo.TBL_CASE c
JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
WHERE c.CO_NM LIKE 'EQUIFAX%' AND s.STAT_CD = 'ESC';
```

**What is the current status of complaint 12278890?**
```sql
SELECT TOP 1 c.CMPL_ID, s.STAT_CD, r.STAT_DESC, s.ASGN_TEAM, s.UPD_TS
FROM dbo.TBL_CASE c
JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
JOIN dbo.REF_STAT_CD r     ON r.STAT_CD = s.STAT_CD
WHERE c.CMPL_ID = 12278890;
```

**How many cases were ever escalated in 2025, by product?**
```sql
SELECT TOP 50 c.PRD_DESC, COUNT(DISTINCT c.CASE_ID) AS cases_ever_escalated
FROM dbo.TBL_CASE c
JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.STAT_CD = 'ESC'
WHERE c.RCV_DT >= '2025-01-01' AND c.RCV_DT < '2026-01-01'
GROUP BY c.PRD_DESC
ORDER BY cases_ever_escalated DESC;
```

**Which open cases have waited longest since their last status change?**
```sql
SELECT TOP 20 c.CMPL_ID, c.CO_NM, s.STAT_CD, s.UPD_TS,
       DATEDIFF(day, s.UPD_TS, SYSDATETIME()) AS days_since_update
FROM dbo.TBL_CASE c
JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
WHERE s.STAT_CD <> 'CLS'
ORDER BY days_since_update DESC;
```
