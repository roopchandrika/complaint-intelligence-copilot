"""Day 4 practice drills against the legacy SQL Server. Read-only: every drill uses copilot_readonly.

Run from the project root:
    python data/legacy/drills_legacy.py            # all drills
    python data/legacy/drills_legacy.py 2          # only drill 2
"""
import re
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import text  # noqa: E402
from sqlalchemy.exc import DBAPIError  # noqa: E402

from data.legacy.legacy_client import engine  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")


def show(rows, limit=15):
    rows = list(rows)
    if not rows:
        print("   (no rows)")
        return
    cols = list(rows[0].keys())
    print("   " + " | ".join(cols))
    for r in rows[:limit]:
        print("   " + " | ".join(str(r[c]) for c in cols))
    if len(rows) > limit:
        print(f"   ... {len(rows) - limit} more rows")


def q(sql, params=None):
    with engine().connect() as conn:
        return list(conn.execute(text(sql), params or {}).mappings())


# ---------------------------------------------------------------------------
def drill1_injection():
    print("\nDRILL 1. SQL injection: string-building vs parameters")
    company = "x' OR '1'='1"
    print(f"   User input: {company!r}")

    unsafe_sql = f"SELECT COUNT(*) AS n FROM dbo.TBL_CASE WHERE CO_NM = '{company}'"
    print(f"\n   UNSAFE (f-string). The SQL that reaches the server is:\n   {unsafe_sql}")
    print(f"   Rows matched: {q(unsafe_sql)[0]['n']:,}   <- the input became code: OR '1'='1' is always true")

    print("\n   SAFE (parameter). SQL text: ... WHERE CO_NM = :co   value sent separately")
    n = q("SELECT COUNT(*) AS n FROM dbo.TBL_CASE WHERE CO_NM = :co", {"co": company})[0]["n"]
    print(f"   Rows matched: {n:,}   <- no company is literally named that")
    print("\n   Because the login is read-only, the unsafe query could only READ too much.")
    print("   With a write-capable login, the same mistake could delete data.")


def drill2_permissions():
    print("\nDRILL 2. Permission matrix for copilot_readonly")
    attempts = {
        "SELECT":        "SELECT TOP 1 CASE_ID FROM dbo.TBL_CASE",
        "INSERT":        "INSERT INTO dbo.REF_STAT_CD VALUES ('XXX', 'x')",
        "UPDATE":        "UPDATE dbo.TBL_CASE SET CO_NM = CO_NM WHERE CASE_ID = 1",
        "DELETE":        "DELETE FROM dbo.TBL_CASE_STATUS WHERE STAT_ID = -1",
        "CREATE TABLE":  "CREATE TABLE dbo.evil (id INT)",
        "DROP TABLE":    "DROP TABLE dbo.TBL_CASE",
        "EXEC sp_who":   "EXEC sp_who",
    }
    print(f"   {'operation':<14} result")
    for name, stmt in attempts.items():
        try:
            with engine().begin() as conn:
                conn.execute(text(stmt))
            result = "ALLOWED"
        except DBAPIError as e:
            raw = str(e.orig)
            msg = raw.split("]")[-1].split("(")[0].strip()
            num = re.search(r"\((\d{3,5})\)", raw)
            result = f"DENIED  - error {num.group(1) if num else '?'}: {msg[:80]}"
        print(f"   {name:<14} {result}")
    print("   (EXEC sp_who is allowed: it is a system procedure outside dbo. It only lists sessions.)")


def drill3_catalog():
    print("\nDRILL 3. Discover the schema using only system catalog views")
    print("\n   3a. Tables:")
    show(q("""SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES
              ORDER BY TABLE_NAME"""))
    print("\n   3b. Columns:")
    show(q("""SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS max_len, IS_NULLABLE
              FROM INFORMATION_SCHEMA.COLUMNS ORDER BY TABLE_NAME, ORDINAL_POSITION"""), limit=30)
    print("\n   3c. Foreign keys (how tables join):")
    show(q("""SELECT fk.name AS fk_name,
                     OBJECT_NAME(fk.parent_object_id)      AS child_table,
                     COL_NAME(fc.parent_object_id, fc.parent_column_id)         AS child_column,
                     OBJECT_NAME(fk.referenced_object_id)  AS parent_table,
                     COL_NAME(fc.referenced_object_id, fc.referenced_column_id) AS parent_column
              FROM sys.foreign_keys fk
              JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = fk.object_id"""))
    print("\n   3d. Row counts:")
    show(q("""SELECT 'TBL_CASE' AS table_name, COUNT(*) AS row_count FROM dbo.TBL_CASE
              UNION ALL SELECT 'TBL_CASE_STATUS', COUNT(*) FROM dbo.TBL_CASE_STATUS
              UNION ALL SELECT 'REF_STAT_CD', COUNT(*) FROM dbo.REF_STAT_CD"""))
    print("\n   3e. What the codes mean, and how often each is the CURRENT status:")
    show(q("""SELECT r.STAT_CD, r.STAT_DESC,
                     SUM(CASE WHEN s.CUR_FLG = 1 THEN 1 ELSE 0 END) AS current_cases,
                     COUNT(s.STAT_ID) AS all_history_rows
              FROM dbo.REF_STAT_CD r LEFT JOIN dbo.TBL_CASE_STATUS s ON s.STAT_CD = r.STAT_CD
              GROUP BY r.STAT_CD, r.STAT_DESC ORDER BY current_cases DESC"""))
    print("\n   3f. The CUR_FLG trap: counting escalations with and without the current flag")
    show(q("""SELECT
                (SELECT COUNT(*) FROM dbo.TBL_CASE_STATUS WHERE STAT_CD = 'ESC')                AS esc_rows_all_history,
                (SELECT COUNT(*) FROM dbo.TBL_CASE_STATUS WHERE STAT_CD = 'ESC' AND CUR_FLG = 1) AS esc_cases_now"""))
    print("   Cases that WERE escalated but are now closed are only in the first number.")


def drill4_dialect():
    print("\nDRILL 4. T-SQL dialect (compare with your Postgres/DuckDB queries)")
    print("\n   4a. TOP instead of LIMIT; DATEFROMPARTS instead of date_trunc; month-level counts:")
    show(q("""SELECT TOP 6 DATEFROMPARTS(YEAR(RCV_DT), MONTH(RCV_DT), 1) AS month, COUNT(*) AS cases
              FROM dbo.TBL_CASE
              GROUP BY DATEFROMPARTS(YEAR(RCV_DT), MONTH(RCV_DT), 1)
              ORDER BY month DESC"""))
    print("\n   4b. DATEDIFF and window functions (same idea as Day 2): hours from received to current status")
    show(q("""SELECT TOP 5 c.CMPL_ID, s.STAT_CD,
                     DATEDIFF(hour, CAST(c.RCV_DT AS DATETIME2), s.UPD_TS) AS hours_open,
                     RANK() OVER (ORDER BY DATEDIFF(hour, CAST(c.RCV_DT AS DATETIME2), s.UPD_TS) DESC) AS rnk
              FROM dbo.TBL_CASE c
              JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
              WHERE s.STAT_CD = 'LGL'
              ORDER BY hours_open DESC"""))
    print("\n   4c. String concatenation with + and CONCAT, and OFFSET/FETCH paging:")
    show(q("""SELECT CONCAT(STAT_CD, ' = ', STAT_DESC) AS code_text, STAT_CD + '/' + STAT_DESC AS plus_text
              FROM dbo.REF_STAT_CD ORDER BY STAT_CD
              OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY"""))


DRILLS = [drill1_injection, drill2_permissions, drill3_catalog, drill4_dialect]

if __name__ == "__main__":
    only = int(sys.argv[1]) if len(sys.argv) > 1 else None
    for i, drill in enumerate(DRILLS, start=1):
        if only is None or only == i:
            drill()
