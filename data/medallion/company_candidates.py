"""Suggest company names that may be the same entity, for a HUMAN to review.

    python data/medallion/company_candidates.py            # top 300 companies
    python data/medallion/company_candidates.py --top 1000

Writes data/medallion/company_candidates.csv with columns:
    name_a, name_b, score, complaints_a, complaints_b, decision
Fill "decision" with yes/no. For every "yes", add a line to seeds/company_map.csv:
    <company_norm of the smaller name>,<the name you want to keep>
then re-run:  python data/medallion/run_pipeline.py --from silver

Fuzzy matching only SUGGESTS. It never merges automatically: in a bank, merging two
different companies is worse than leaving two spellings of one company.
"""
import argparse
import csv
from pathlib import Path

import duckdb
from rapidfuzz import fuzz, process

OUT = Path(__file__).resolve().parent / "company_candidates.csv"

ap = argparse.ArgumentParser()
ap.add_argument("--top", type=int, default=300)
ap.add_argument("--min-score", type=int, default=88)
args = ap.parse_args()

con = duckdb.connect("data/warehouse.duckdb", read_only=True)
rows = con.sql(f"""SELECT company, complaints FROM gold.company_scorecard
                   ORDER BY complaints DESC LIMIT {int(args.top)}""").fetchall()
con.close()

names = [r[0] for r in rows]
volume = dict(rows)
pairs = {}
for name in names:
    for other, score, _ in process.extract(name, names, scorer=fuzz.token_set_ratio, limit=6):
        if other != name and score >= args.min_score:
            key = tuple(sorted((name, other)))
            pairs[key] = max(score, pairs.get(key, 0))

with OUT.open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["name_a", "name_b", "score", "complaints_a", "complaints_b", "decision"])
    for (a, b), score in sorted(pairs.items(), key=lambda kv: -kv[1]):
        w.writerow([a, b, round(score), volume[a], volume[b], ""])

print(f"{len(pairs)} candidate pairs written to {OUT}")
print("Review each pair: same legal entity? Mark yes/no. Common false matches: different")
print("banks with similar names ('First National Bank of X' vs 'of Y'), parent vs subsidiary.")
