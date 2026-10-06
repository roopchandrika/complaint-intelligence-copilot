"""Day 3: copy the `complaints` table from DuckDB (Day 2) into Postgres.

Run from the project root, with Postgres running (docker compose up -d):
    python data/load_postgres.py

Takes roughly 3-10 minutes for ~18M rows. The table is created WITHOUT any
indexes on purpose: Day 3 measures queries before and after adding them.

Method 1: DuckDB's postgres extension (fast binary copy).
Method 2 (automatic fallback): export to a temporary CSV, then Postgres COPY.
"""
import os
import sys
import tempfile
import time

import duckdb
import psycopg

sys.stdout.reconfigure(encoding="utf-8")

DUCKDB_FILE = "data/complaints.duckdb"
PG_DSN = os.environ.get("PG_DSN", "postgresql://postgres:postgres@localhost:5433/complaints")

CREATE_TABLE = """
DROP TABLE IF EXISTS complaints CASCADE;
CREATE TABLE complaints (
    date_received                 date,
    product                       text,
    sub_product                   text,
    issue                         text,
    sub_issue                     text,
    consumer_complaint_narrative  text,
    company_public_response       text,
    company                       text,
    state                         text,
    zip_code                      text,
    tags                          text,
    consumer_consent_provided     text,
    submitted_via                 text,
    date_sent_to_company          date,
    company_response_to_consumer  text,
    timely_response               text,
    consumer_disputed             text,
    complaint_id                  bigint
);
"""
COLUMNS = [
    "date_received", "product", "sub_product", "issue", "sub_issue",
    "consumer_complaint_narrative", "company_public_response", "company", "state",
    "zip_code", "tags", "consumer_consent_provided", "submitted_via",
    "date_sent_to_company", "company_response_to_consumer", "timely_response",
    "consumer_disputed", "complaint_id",
]
COL_LIST = ", ".join(COLUMNS)


def load_with_extension(duck: duckdb.DuckDBPyConnection) -> None:
    duck.execute("INSTALL postgres; LOAD postgres;")
    duck.execute(f"ATTACH '{PG_DSN}' AS pg (TYPE postgres)")
    duck.execute(f"INSERT INTO pg.public.complaints ({COL_LIST}) SELECT {COL_LIST} FROM complaints")
    duck.execute("DETACH pg")


def load_with_csv(duck: duckdb.DuckDBPyConnection, pg: psycopg.Connection) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        csv_path = os.path.join(tmp, "complaints.csv").replace("\\", "/")
        print("  exporting to a temporary CSV ...")
        duck.execute(f"COPY (SELECT {COL_LIST} FROM complaints) TO '{csv_path}' (HEADER, DELIMITER ',')")
        print("  streaming into Postgres with COPY ...")
        with pg.cursor() as cur, open(csv_path, "rb") as f:
            with cur.copy(f"COPY complaints ({COL_LIST}) FROM STDIN WITH (FORMAT csv, HEADER true)") as copy:
                while chunk := f.read(8 * 1024 * 1024):
                    copy.write(chunk)


def main() -> None:
    start = time.time()
    duck = duckdb.connect(DUCKDB_FILE, read_only=True)
    expected = duck.sql("SELECT count(*) FROM complaints").fetchone()[0]
    print(f"DuckDB rows to copy: {expected:,}")

    with psycopg.connect(PG_DSN, autocommit=True) as pg:
        pg.execute(CREATE_TABLE)
        try:
            print("Loading with the DuckDB postgres extension ...")
            load_with_extension(duck)
        except Exception as e:  # e.g. no internet to download the extension
            print(f"  extension method failed ({type(e).__name__}: {str(e)[:120]})")
            print("Falling back to CSV + COPY ...")
            pg.execute("TRUNCATE complaints")
            load_with_csv(duck, pg)

        print("Running VACUUM ANALYZE (collects statistics for the planner) ...")
        pg.execute("VACUUM ANALYZE complaints")

        rows = pg.execute("SELECT count(*) FROM complaints").fetchone()[0]
        size = pg.execute("SELECT pg_size_pretty(pg_total_relation_size('complaints'))").fetchone()[0]
        print(f"Postgres rows: {rows:,}  (expected {expected:,})  table size: {size}")
        if rows != expected:
            sys.exit("Row counts do not match - check the messages above.")
    print(f"Done in {time.time() - start:.0f} s")


if __name__ == "__main__":
    main()