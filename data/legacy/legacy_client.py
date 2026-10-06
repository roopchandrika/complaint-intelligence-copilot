"""Read-only, parameterized access to the bank's legacy case system (Day 4).

Every function:
  - connects as copilot_readonly (SELECT only - the database itself refuses writes)
  - sends values as bound parameters, never by pasting them into the SQL text
  - limits how many rows come back and how long a query may run

Later (Day 17) the agent calls these functions as tools.
"""
import sys
from datetime import date
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from sqlalchemy import create_engine, event, text  # noqa: E402
from sqlalchemy.engine import Engine  # noqa: E402

from data.legacy.legacy_db import require, sqlalchemy_url  # noqa: E402

MAX_ROWS = 500
QUERY_TIMEOUT_S = 30

# Allow-list for sorting: user input picks a KEY, the SQL only ever contains our own VALUES.
SORT_COLUMNS = {"date": "c.RCV_DT", "company": "c.CO_NM", "complaint": "c.CMPL_ID"}


def get_engine() -> Engine:
    engine = create_engine(
        sqlalchemy_url("copilot_readonly", require("LEGACY_RO_PASSWORD"), read_only=True),
        pool_size=5,
        max_overflow=5,
        pool_pre_ping=True,          # test a pooled connection before using it
        pool_recycle=1800,           # reconnect before network devices drop idle connections
        connect_args={"timeout": 10},  # login timeout in seconds
    )

    @event.listens_for(engine, "connect")
    def _set_query_timeout(dbapi_conn, _record):
        dbapi_conn.timeout = QUERY_TIMEOUT_S   # pyodbc: cancel any query running longer than this

    return engine


_ENGINE: Engine | None = None


def engine() -> Engine:
    global _ENGINE
    if _ENGINE is None:
        _ENGINE = get_engine()
    return _ENGINE


def _clamp(limit: int) -> int:
    return max(1, min(int(limit), MAX_ROWS))


def _escape_like(value: str) -> str:
    """Make %, _ and [ in user input literal characters inside a LIKE pattern."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_").replace("[", "\\[")


# ---------- tool functions ----------
def current_status(complaint_id: int) -> dict | None:
    """Current status of one case, looked up by its CFPB complaint ID."""
    sql = text("""
        SELECT c.CMPL_ID, c.CO_NM, c.PRD_DESC, c.ISS_DESC, c.RCV_DT,
               s.STAT_CD, r.STAT_DESC, s.ASGN_TEAM, s.UPD_TS
        FROM dbo.TBL_CASE c
        JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
        JOIN dbo.REF_STAT_CD r     ON r.STAT_CD = s.STAT_CD
        WHERE c.CMPL_ID = :cid
    """)
    with engine().connect() as conn:
        row = conn.execute(sql, {"cid": int(complaint_id)}).mappings().first()
    return dict(row) if row else None


def case_history(complaint_id: int) -> list[dict]:
    """Every status change of one case, oldest first."""
    sql = text("""
        SELECT s.UPD_TS, s.STAT_CD, r.STAT_DESC, s.ASGN_TEAM, s.CUR_FLG
        FROM dbo.TBL_CASE c
        JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID
        JOIN dbo.REF_STAT_CD r     ON r.STAT_CD = s.STAT_CD
        WHERE c.CMPL_ID = :cid
        ORDER BY s.UPD_TS
    """)
    with engine().connect() as conn:
        return [dict(r) for r in conn.execute(sql, {"cid": int(complaint_id)}).mappings()]


def escalated_cases(company: str, since: date, limit: int = 50, sort: str = "date") -> list[dict]:
    """Cases currently escalated or on legal hold for companies whose name starts with `company`."""
    order_by = SORT_COLUMNS[sort]                     # KeyError for anything not in the allow-list
    sql = text(f"""
        SELECT TOP (:lim) c.CMPL_ID, c.CO_NM, c.RCV_DT, c.ISS_DESC, s.STAT_CD, s.ASGN_TEAM
        FROM dbo.TBL_CASE c
        JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
        WHERE c.CO_NM LIKE :pattern ESCAPE '\\'
          AND c.RCV_DT >= :since
          AND s.STAT_CD IN ('ESC', 'LGL')
        ORDER BY {order_by} DESC
    """)
    params = {"lim": _clamp(limit), "pattern": _escape_like(company) + "%", "since": since}
    with engine().connect() as conn:
        return [dict(r) for r in conn.execute(sql, params).mappings()]


def status_counts(company: str | None = None) -> list[dict]:
    """How many cases are in each current status, optionally for one company (prefix match)."""
    # Two fixed SQL texts (with / without the company filter). Only the VALUE comes from the caller.
    company_filter = "WHERE c.CO_NM LIKE :pattern ESCAPE '\\'" if company else ""
    sql = text(f"""
        SELECT r.STAT_CD, r.STAT_DESC, COUNT(*) AS cases
        FROM dbo.TBL_CASE c
        JOIN dbo.TBL_CASE_STATUS s ON s.CASE_ID = c.CASE_ID AND s.CUR_FLG = 1
        JOIN dbo.REF_STAT_CD r     ON r.STAT_CD = s.STAT_CD
        {company_filter}
        GROUP BY r.STAT_CD, r.STAT_DESC
        ORDER BY cases DESC
    """)
    params = {"pattern": _escape_like(company) + "%"} if company else {}
    with engine().connect() as conn:
        return [dict(r) for r in conn.execute(sql, params).mappings()]


if __name__ == "__main__":
    # Quick manual check:  python data/legacy/legacy_client.py
    from pprint import pprint

    sys.stdout.reconfigure(encoding="utf-8")
    print("Status counts:")
    pprint(status_counts())
    with engine().connect() as conn:
        some_id = conn.execute(text("SELECT TOP 1 CMPL_ID FROM dbo.TBL_CASE ORDER BY CMPL_ID")).scalar()
    print(f"\nCurrent status of complaint {some_id}:")
    pprint(current_status(some_id))
    print(f"\nHistory of complaint {some_id}:")
    pprint(case_history(some_id))
    print("\nEscalated Equifax cases since 2024 (top 5):")
    pprint(escalated_cases("EQUIFAX", date(2024, 1, 1), limit=5))
