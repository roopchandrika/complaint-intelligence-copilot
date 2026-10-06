"""Day 4: prove the copilot's database login can READ but never WRITE.

Run (SQL Server must be running and set up):   pytest tests/test_readonly.py -v
"""
from datetime import date

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from data.legacy import legacy_client as lc


@pytest.fixture(scope="module")
def engine():
    try:
        eng = lc.engine()
        with eng.connect() as conn:
            conn.execute(text("SELECT 1"))
        return eng
    except Exception as e:  # make the reason obvious instead of 9 confusing failures
        pytest.fail(f"Cannot connect as copilot_readonly. Is SQL Server running and set up?\n{e}")


# ---------- reads work ----------
def test_select_works(engine):
    with engine.connect() as conn:
        assert conn.execute(text("SELECT COUNT(*) FROM dbo.TBL_CASE")).scalar() > 0


def test_connected_as_readonly_login(engine):
    with engine.connect() as conn:
        assert conn.execute(text("SELECT SUSER_SNAME()")).scalar() == "copilot_readonly"


def test_every_case_has_exactly_one_current_status(engine):
    with engine.connect() as conn:
        bad = conn.execute(text("""
            SELECT COUNT(*) FROM (
                SELECT CASE_ID FROM dbo.TBL_CASE_STATUS
                GROUP BY CASE_ID HAVING SUM(CAST(CUR_FLG AS INT)) <> 1
            ) x
        """)).scalar()
    assert bad == 0


# ---------- writes and schema changes are refused ----------
@pytest.mark.parametrize("stmt", [
    "INSERT INTO dbo.REF_STAT_CD (STAT_CD, STAT_DESC) VALUES ('XXX', 'hack')",
    "UPDATE dbo.TBL_CASE SET CO_NM = 'x' WHERE CASE_ID = 1",
    "DELETE FROM dbo.TBL_CASE_STATUS WHERE STAT_ID = 1",
    "TRUNCATE TABLE dbo.TBL_CASE_STATUS",
    "CREATE TABLE dbo.evil (id INT)",
    "DROP TABLE dbo.TBL_CASE",
    "ALTER TABLE dbo.TBL_CASE ADD hacked INT",
])
def test_writes_are_denied(engine, stmt):
    with pytest.raises(DBAPIError):
        with engine.begin() as conn:           # begin() commits if no error is raised
            conn.execute(text(stmt))


def test_data_unchanged_after_write_attempts(engine):
    with engine.connect() as conn:
        assert conn.execute(text("SELECT COUNT(*) FROM dbo.REF_STAT_CD")).scalar() == 5


# ---------- injection attempts are treated as plain values ----------
def test_injection_in_company_name_returns_nothing():
    assert lc.escalated_cases("x' OR '1'='1", date(2000, 1, 1)) == []


def test_like_wildcard_is_literal():
    # "%" must not mean "any company": it is escaped, so it matches only names starting with "%"
    assert lc.escalated_cases("%", date(2000, 1, 1)) == []


def test_sort_must_be_in_allow_list():
    with pytest.raises(KeyError):
        lc.escalated_cases("EQUIFAX", date(2000, 1, 1), sort="RCV_DT; DROP TABLE dbo.TBL_CASE")


def test_limit_is_clamped():
    rows = lc.escalated_cases("", date(2000, 1, 1), limit=100_000)
    assert len(rows) <= lc.MAX_ROWS
