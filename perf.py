"""Day 3 query-performance tool for Postgres.

Run from the project root (Postgres must be running):

  python perf.py bench --tag before        # time every query in sql/pg/perf_queries.sql, save plans
  python perf.py exec sql/pg/fixes.sql     # run a .sql file statement by statement (indexes, drills, ...)
  python perf.py bench --tag after         # time again after the fixes
  python perf.py report                    # before/after table for PERF.md
  python perf.py explain Q7                # print the EXPLAIN ANALYZE plan of one query

Options:  --runs N (timed runs per query, default 3)   --only Q7,P1 (subset of queries)

Results go to perf_results.csv, plans to plans/<tag>/<query>.txt, the table to perf_table.md.
"""
import argparse
import csv
import os
import re
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

import psycopg

sys.stdout.reconfigure(encoding="utf-8")

PG_DSN = os.environ.get("PG_DSN", "postgresql://postgres:postgres@localhost:5433/complaints")
QUERY_FILE = Path("sql/pg/perf_queries.sql")
RESULTS = Path("perf_results.csv")
PLANS = Path("plans")
TIMEOUT_MS = 600_000  # 10 minutes per statement

ID_RE = re.compile(r"^--\s*([A-Z]\d+[a-z]?(?:-MV)?)\.\s*(.*)")
SCAN_RE = re.compile(
    r"((?:Parallel )?(?:Seq Scan|Index Only Scan|Bitmap Index Scan|Bitmap Heap Scan|Index Scan)"
    r"(?: using \S+)? on \S+)"
)


# ---------- helpers ----------
def split_statements(text: str) -> list[str]:
    parts = re.split(r";[ \t]*(?:\r?\n|$)", text)
    return [p.strip() for p in parts if re.sub(r"--[^\n]*", "", p).strip()]


def load_queries(only: set[str] | None = None) -> list[tuple[str, str, str]]:
    """Return (id, title, sql) for each query in the perf file."""
    queries = []
    for stmt in split_statements(QUERY_FILE.read_text(encoding="utf-8")):
        first = stmt.splitlines()[0]
        m = ID_RE.match(first)
        qid, title = (m.group(1), m.group(2)) if m else (f"S{len(queries) + 1}", first[:80])
        if only and qid not in only:
            continue
        queries.append((qid, title, stmt))
    return queries


def connect() -> psycopg.Connection:
    conn = psycopg.connect(PG_DSN, autocommit=True)
    conn.execute(f"SET statement_timeout = {TIMEOUT_MS}")
    return conn


def explain(conn: psycopg.Connection, sql: str) -> list[str]:
    rows = conn.execute("EXPLAIN (ANALYZE, BUFFERS) " + sql).fetchall()
    return [r[0] for r in rows]


def main_scans(plan: list[str]) -> str:
    """The table access methods used, e.g. 'Parallel Seq Scan on complaints'."""
    found = []
    for line in plan:
        m = SCAN_RE.search(line)
        if m and m.group(1) not in found:
            found.append(m.group(1))
    return "; ".join(found) if found else "(no table scan)"


def fmt_ms(ms: float | None) -> str:
    if ms is None:
        return "-"
    return f"{ms:,.1f} ms" if ms < 10 else f"{ms:,.0f} ms"


def exec_time(plan: list[str]) -> str:
    for line in plan:
        if line.strip().startswith("Execution Time"):
            return line.split(":")[1].strip()
    return ""


# ---------- commands ----------
def cmd_bench(args) -> None:
    only = set(args.only.split(",")) if args.only else None
    queries = load_queries(only)
    plan_dir = PLANS / args.tag
    plan_dir.mkdir(parents=True, exist_ok=True)
    new_file = not RESULTS.exists()

    with connect() as conn, RESULTS.open("a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if new_file:
            writer.writerow(["tag", "query", "title", "median_ms", "runs", "scans", "measured_at"])
        for qid, title, sql in queries:
            print(f"[{args.tag}] {qid}: {title}")
            try:
                conn.execute(sql).fetchall()                      # warm-up run (not timed)
                times = []
                for _ in range(args.runs):
                    t0 = time.perf_counter()
                    conn.execute(sql).fetchall()
                    times.append((time.perf_counter() - t0) * 1000)
                med = statistics.median(times)
                plan = explain(conn, sql)
                (plan_dir / f"{qid}.txt").write_text(sql + "\n\n" + "\n".join(plan), encoding="utf-8")
                scans = main_scans(plan)
                print(f"      median {fmt_ms(med)} over {args.runs} runs | {scans}")
                writer.writerow([args.tag, qid, title, f"{med:.2f}", args.runs, scans,
                                 datetime.now().isoformat(timespec="seconds")])
            except psycopg.errors.UndefinedTable:
                print("      skipped: a table/view it needs does not exist yet")
            except psycopg.Error as e:
                print(f"      ERROR: {str(e).splitlines()[0]}")
            f.flush()
    print(f"\nSaved timings to {RESULTS} and plans to {plan_dir}/")


def cmd_exec(args) -> None:
    text = Path(args.sql_file).read_text(encoding="utf-8")
    with connect() as conn:
        for i, stmt in enumerate(split_statements(text), start=1):
            title = next((ln.strip("- ").strip() for ln in stmt.splitlines() if ln.strip().startswith("--")),
                         stmt.splitlines()[0][:90])
            print("=" * 100)
            print(f"[{i}] {title}")
            t0 = time.perf_counter()
            try:
                cur = conn.execute(stmt)
                if cur.description:
                    rows = cur.fetchall()
                    cols = [d.name for d in cur.description]
                    if cols == ["QUERY PLAN"]:
                        for r in rows:
                            print("   " + r[0])
                    else:
                        print("   " + " | ".join(cols))
                        for r in rows[: args.rows]:
                            print("   " + " | ".join("NULL" if v is None else str(v) for v in r))
                        if len(rows) > args.rows:
                            print(f"   ... {len(rows) - args.rows} more rows")
                print(f"({(time.perf_counter() - t0) * 1000:,.0f} ms)")
            except psycopg.Error as e:
                print(f"ERROR: {str(e).splitlines()[0]}")


def cmd_explain(args) -> None:
    queries = load_queries({args.query})
    if not queries:
        sys.exit(f"No query with id {args.query} in {QUERY_FILE}")
    _, title, sql = queries[0]
    with connect() as conn:
        print(f"{args.query}: {title}\n")
        print("\n".join(explain(conn, sql)))


def cmd_report(args) -> None:
    if not RESULTS.exists():
        sys.exit("No results yet. Run: python perf.py bench --tag before")
    latest: dict[tuple[str, str], dict] = {}
    with RESULTS.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            latest[(row["tag"], row["query"])] = row          # later rows win

    order = [q[0] for q in load_queries()]
    lines = ["| Query | Question | Before | After | Speedup | Plan before | Plan after |",
             "|---|---|---|---|---|---|---|"]
    for qid in order:
        after = latest.get(("after", qid))
        before = latest.get(("before", qid))
        if qid.endswith("-MV"):                                   # compare MV version with the original query
            before = latest.get(("before", qid[:-3]))
        if not before and not after:
            continue
        b = float(before["median_ms"]) if before else None
        a = float(after["median_ms"]) if after else None
        speed = f"{b / a:,.0f}x" if a and b else ""
        title = re.sub(r"^Business question\s*:?\s*", "", (after or before)["title"])
        lines.append(
            f"| {qid} | {title} | {fmt_ms(b)} | {fmt_ms(a)} | {speed} | "
            f"{before['scans'] if before else '-'} | {after['scans'] if after else '-'} |"
        )
    table = "\n".join(lines)
    Path("perf_table.md").write_text(table + "\n", encoding="utf-8")
    print(table)
    print("\nSaved to perf_table.md (paste it into PERF.md)")


def main() -> None:
    ap = argparse.ArgumentParser(description="Day 3 Postgres performance tool")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("bench", help="time all queries and save plans")
    b.add_argument("--tag", required=True, help="label for this run, e.g. before / after")
    b.add_argument("--runs", type=int, default=3)
    b.add_argument("--only", help="comma-separated query ids, e.g. Q7,P1")
    b.set_defaults(func=cmd_bench)

    e = sub.add_parser("exec", help="run a .sql file statement by statement")
    e.add_argument("sql_file")
    e.add_argument("--rows", type=int, default=20)
    e.set_defaults(func=cmd_exec)

    x = sub.add_parser("explain", help="print the EXPLAIN ANALYZE plan of one query")
    x.add_argument("query")
    x.set_defaults(func=cmd_explain)

    r = sub.add_parser("report", help="before/after markdown table")
    r.set_defaults(func=cmd_report)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()