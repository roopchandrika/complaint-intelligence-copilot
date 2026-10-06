"""Day 6: run the whole medallion pipeline with one command.

    python data/medallion/run_pipeline.py                 # Bronze -> Silver -> Gold -> DQ report
    python data/medallion/run_pipeline.py --from silver   # reuse Bronze, rebuild Silver and Gold
    python data/medallion/run_pipeline.py --snapshot      # also save Bronze as a Parquet snapshot

Everything lives in data/warehouse.duckdb, in three schemas: bronze, silver, gold.
Re-running gives identical results (idempotent): tables are replaced, not appended to.
"""
import argparse
import sys
import time
from pathlib import Path

import duckdb

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from bronze import build_bronze  # noqa: E402
from dq_report import build_report  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

CSV = Path("data/raw/complaints.csv")
WAREHOUSE = Path("data/warehouse.duckdb")
SNAPSHOTS = Path("data/lake/bronze")
REPORT = HERE / "DQ_REPORT.md"
SEEDS = (HERE / "seeds").as_posix()


def split_statements(text: str) -> list[str]:
    import re
    parts = re.split(r";[ \t]*(?:\r?\n|$)", text)
    return [p.strip() for p in parts if re.sub(r"--[^\n]*", "", p).strip()]


def run_sql_file(con, path: Path) -> None:
    text = path.read_text(encoding="utf-8").replace("{{SEEDS}}", SEEDS)
    for stmt in split_statements(text):
        con.execute(stmt)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", choices=["bronze", "silver", "gold"], default="bronze")
    ap.add_argument("--snapshot", action="store_true", help="save Bronze as Parquet in data/lake/bronze/")
    args = ap.parse_args()

    con = duckdb.connect(str(WAREHOUSE))
    con.execute("SET preserve_insertion_order = false")   # lets DuckDB use less memory on big tables
    timings: dict[str, float] = {}
    order = ["bronze", "silver", "gold"]

    if order.index(args.start) <= 0:
        t = time.time()
        print(f"BRONZE  reading {CSV} ...")
        info = build_bronze(con, CSV, SNAPSHOTS if args.snapshot else None)
        timings["bronze"] = time.time() - t
        print(f"        {info['rows']:,} rows, batch {info['batch_id']} ({timings['bronze']:.0f} s)")
        if info["missing"]:
            print(f"        columns missing from the file (kept as empty): {', '.join(info['missing'])}")

    if order.index(args.start) <= 1:
        t = time.time()
        print("SILVER  cleaning, standardizing, deduplicating ...")
        run_sql_file(con, HERE / "02_silver.sql")
        timings["silver"] = time.time() - t
        print(f"        {con.sql('SELECT count(*) FROM silver.complaints').fetchone()[0]:,} rows, "
              f"{con.sql('SELECT count(*) FROM silver.complaints_rejects').fetchone()[0]:,} rejected "
              f"({timings['silver']:.0f} s)")

    t = time.time()
    print("GOLD    building business tables ...")
    run_sql_file(con, HERE / "03_gold.sql")
    timings["gold"] = time.time() - t
    print(f"        done ({timings['gold']:.0f} s)")

    t = time.time()
    checks = build_report(con, REPORT, timings)
    print(f"REPORT  {REPORT}")
    for name, ok in checks:
        print(f"        {'PASS' if ok else 'FAIL'}  {name}")
    con.close()
    if not all(ok for _, ok in checks):
        sys.exit("One or more reconciliation checks FAILED - do not trust Gold until fixed.")


if __name__ == "__main__":
    main()
