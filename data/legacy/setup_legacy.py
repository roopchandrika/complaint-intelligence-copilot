"""Day 4: build the fictional bank's legacy case system in SQL Server.

Run from the project root, after `docker compose -f docker-compose.legacy.yml up -d`:
    python data/legacy/setup_legacy.py              # full setup
    python data/legacy/setup_legacy.py --dry-run    # only prepare the data, do not touch SQL Server

Steps (all as the admin login `sa` - the copilot itself never writes):
  1. wait for SQL Server to accept connections
  2. run 01_schema.sql            (database, tables, indexes, status codes)
  3. load 50,000 complaints from data/complaints.duckdb into dbo.TBL_CASE
  4. generate a status history for every case into dbo.TBL_CASE_STATUS
  5. run 02_readonly_login.sql    (create the read-only login copilot_readonly)
"""
import argparse
import random
import re
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

if __package__ in (None, ""):                                    # allow "python data/legacy/setup_legacy.py"
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import duckdb  # noqa: E402

from data.legacy.legacy_db import DATABASE, odbc_conn_str, require  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

HERE = Path(__file__).resolve().parent
DUCKDB_FILE = "data/complaints.duckdb"
SAMPLE_SIZE = 50_000
BATCH = 5_000
SEED = 42
TEAMS = ["Tier1", "Tier2", "Complaints-Exec", "Legal"]


# ---------- SQL helpers ----------
def split_batches(sql_text: str) -> list[str]:
    """Split a T-SQL script on GO lines (GO is a client command, not T-SQL)."""
    batches = re.split(r"^\s*GO\s*;?\s*$", sql_text, flags=re.IGNORECASE | re.MULTILINE)
    return [b.strip() for b in batches if re.sub(r"--[^\n]*", "", b).strip()]


def run_script(conn, path: Path, replacements: dict[str, str] | None = None) -> None:
    text = path.read_text(encoding="utf-8")
    for key, value in (replacements or {}).items():
        text = text.replace("{{" + key + "}}", value)
    cur = conn.cursor()
    for batch in split_batches(text):
        cur.execute(batch)
        while cur.nextset():                                      # drain all result sets of the batch
            pass
    print(f"  ran {path.name}")


def wait_for_server(timeout_s: int = 180):
    import pyodbc

    conn_str = odbc_conn_str("sa", require("MSSQL_SA_PASSWORD"), database="master")
    start = time.time()
    while True:
        try:
            return pyodbc.connect(conn_str, autocommit=True, timeout=5)
        except pyodbc.Error as e:
            if time.time() - start > timeout_s:
                raise SystemExit(f"SQL Server did not accept connections within {timeout_s}s:\n{e}")
            print("  waiting for SQL Server ...")
            time.sleep(5)


# ---------- data preparation ----------
def load_sample() -> list[tuple]:
    con = duckdb.connect(DUCKDB_FILE, read_only=True)
    # CAST to VARCHAR: columns missing from the source CSV were stored as all-NULL non-text columns
    rows = con.execute(f"""
        SELECT CAST(complaint_id AS BIGINT)               AS CMPL_ID,
               left(CAST(product AS VARCHAR), 100)                        AS PRD_DESC,
               left(CAST(issue AS VARCHAR), 255)                          AS ISS_DESC,
               left(CAST(company AS VARCHAR), 255)                        AS CO_NM,
               left(CAST(state AS VARCHAR), 2)                            AS ST_CD,
               CAST(date_received AS DATE)               AS RCV_DT,
               left(CAST(submitted_via AS VARCHAR), 30)                   AS CHNL,
               left(CAST(consumer_complaint_narrative AS VARCHAR), 4000)  AS NARR_TXT,
               CAST(company_response_to_consumer AS VARCHAR) AS RESP
        FROM complaints
        WHERE complaint_id IS NOT NULL AND date_received IS NOT NULL
        USING SAMPLE reservoir({SAMPLE_SIZE} ROWS) REPEATABLE ({SEED})
    """).fetchall()
    con.close()
    return rows


def status_path(rng: random.Random, response: str | None) -> list[str]:
    """Lifecycle: open -> investigation -> maybe escalated -> maybe legal hold -> maybe closed.

    Escalated cases are more likely to stay open. Even when the company has answered the CFPB
    ("Closed with ..."), about 20% of cases are still open inside the bank (remediation pending),
    so the case system has real open, escalated and legal-hold work to query.
    """
    path = ["OPN", "INV"]
    escalated = rng.random() < 0.12
    if escalated:
        path.append("ESC")
        if rng.random() < 0.25:
            path.append("LGL")
    answered = bool(response) and response.startswith("Closed")
    close_probability = (0.5 if escalated else 0.85) if answered else 0.0
    if rng.random() < close_probability:
        path.append("CLS")
    return path


def build_status_rows(case_rows: list[tuple], responses: dict[int, str]) -> list[tuple]:
    """case_rows: (CASE_ID, CMPL_ID, RCV_DT). Returns (CASE_ID, STAT_CD, ASGN_TEAM, UPD_TS, CUR_FLG)."""
    rng = random.Random(SEED)
    now = datetime.now().replace(microsecond=0)
    out = []
    for case_id, cmpl_id, rcv_dt in case_rows:
        path = status_path(rng, responses.get(cmpl_id))
        ts = datetime.combine(rcv_dt, datetime.min.time()) + timedelta(hours=rng.randint(1, 8))
        for i, code in enumerate(path):
            ts = min(ts + timedelta(hours=rng.randint(2, 96)), now)
            team = "Legal" if code == "LGL" else ("Complaints-Exec" if code == "ESC" else rng.choice(TEAMS[:2]))
            out.append((case_id, code, team, ts, 1 if i == len(path) - 1 else 0))
    return out


# ---------- main ----------
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="prepare data only, no SQL Server")
    args = ap.parse_args()
    t0 = time.time()

    print(f"1. Sampling {SAMPLE_SIZE:,} complaints from {DUCKDB_FILE} ...")
    sample = load_sample()
    responses = {r[0]: r[8] for r in sample}
    case_values = [r[:8] for r in sample]
    print(f"   {len(case_values):,} rows sampled")

    if args.dry_run:
        fake_cases = [(i + 1, r[0], r[5]) for i, r in enumerate(case_values)]
        statuses = build_status_rows(fake_cases, responses)
        current = [s for s in statuses if s[4] == 1]
        counts = {c: sum(1 for s in current if s[1] == c) for c in ["OPN", "INV", "ESC", "LGL", "CLS"]}
        print(f"   dry run: {len(statuses):,} status rows; current status counts: {counts}")
        print("   example case history:", [s[1] for s in statuses if s[0] == fake_cases[0][0]])
        return

    ro_password = require("LEGACY_RO_PASSWORD")
    print("2. Connecting to SQL Server as sa ...")
    conn = wait_for_server()

    print("3. Creating database and tables ...")
    run_script(conn, HERE / "01_schema.sql")
    conn.execute(f"USE {DATABASE}")

    print("4. Loading cases ...")
    cur = conn.cursor()
    cur.fast_executemany = True                                   # send rows in batches: 10-100x faster
    insert_case = ("INSERT INTO dbo.TBL_CASE (CMPL_ID, PRD_DESC, ISS_DESC, CO_NM, ST_CD, RCV_DT, CHNL, NARR_TXT) "
                   "VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    for i in range(0, len(case_values), BATCH):
        cur.executemany(insert_case, case_values[i:i + BATCH])
    case_rows = conn.execute("SELECT CASE_ID, CMPL_ID, RCV_DT FROM dbo.TBL_CASE").fetchall()
    print(f"   {len(case_rows):,} cases loaded")

    print("5. Generating and loading status history ...")
    case_rows = [(r[0], r[1], r[2] if isinstance(r[2], date) else date.fromisoformat(str(r[2]))) for r in case_rows]
    statuses = build_status_rows(case_rows, responses)
    insert_status = ("INSERT INTO dbo.TBL_CASE_STATUS (CASE_ID, STAT_CD, ASGN_TEAM, UPD_TS, CUR_FLG) "
                     "VALUES (?, ?, ?, ?, ?)")
    for i in range(0, len(statuses), BATCH):
        cur.executemany(insert_status, statuses[i:i + BATCH])
    print(f"   {len(statuses):,} status rows loaded")

    print("6. Creating the read-only login copilot_readonly ...")
    run_script(conn, HERE / "02_readonly_login.sql", {"RO_PASSWORD": ro_password.replace("'", "''")})

    print("\nSummary (current status of each case):")
    for code, desc, n in conn.execute("""
        SELECT s.STAT_CD, r.STAT_DESC, COUNT(*)
        FROM dbo.TBL_CASE_STATUS s JOIN dbo.REF_STAT_CD r ON r.STAT_CD = s.STAT_CD
        WHERE s.CUR_FLG = 1
        GROUP BY s.STAT_CD, r.STAT_DESC ORDER BY COUNT(*) DESC
    """).fetchall():
        print(f"   {code} {desc:<22} {n:>7,}")
    conn.close()
    print(f"\nDone in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()