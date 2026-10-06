"""Run every query in a .sql file against data/complaints.duckdb and print the results.

Usage (from the project root):
    python run_sql.py sql/analysis.sql          # run all queries
    python run_sql.py sql/analysis.sql 3        # run only query number 3
    python run_sql.py sql/drills.sql --rows 30  # show more rows per result
    python run_sql.py some.sql --db data/warehouse.duckdb   # use another database file

Statements are separated by a semicolon at the end of a line.
The comment lines above each query are printed as its title.
"""
import argparse
import re
import time

import sys

import duckdb

sys.stdout.reconfigure(encoding="utf-8")  # box-drawing characters print correctly in any Windows terminal

DB = "data/complaints.duckdb"


def split_statements(text: str) -> list[str]:
    parts = re.split(r";[ \t]*(?:\r?\n|$)", text)
    return [p.strip() for p in parts if re.sub(r"--[^\n]*", "", p).strip()]


def title_of(stmt: str) -> str:
    comments = [ln.strip("- ").strip() for ln in stmt.splitlines() if ln.strip().startswith("--")]
    return " | ".join(comments) if comments else stmt.splitlines()[0][:80]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("only", nargs="?", type=int, help="run only this query number (1-based)")
    ap.add_argument("--rows", type=int, default=15, help="rows to display per result")
    ap.add_argument("--db", default=DB, help="DuckDB file (default: data/complaints.duckdb)")
    args = ap.parse_args()

    with open(args.sql_file, encoding="utf-8") as f:
        statements = split_statements(f.read())

    con = duckdb.connect(args.db)
    for i, stmt in enumerate(statements, start=1):
        if args.only and i != args.only:
            continue
        print("=" * 100)
        print(f"[{i}] {title_of(stmt)}")
        start = time.perf_counter()
        try:
            rel = con.sql(stmt)
            if rel is not None:
                rel.show(max_rows=args.rows, max_width=200)
            print(f"({(time.perf_counter() - start) * 1000:.0f} ms)")
        except duckdb.Error as e:
            print(f"ERROR: {e}")
    con.close()


if __name__ == "__main__":
    main()
