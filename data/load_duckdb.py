"""Day 2: load the CFPB complaints CSV into a DuckDB table called `complaints`.

Run from the project root:  python data/load_duckdb.py
Takes a few minutes for ~18M rows and creates data/complaints.duckdb (a few GB).

The script reads the CSV's real header, matches each column to a clean name
(ignoring case, spaces and punctuation), and casts types explicitly, so the
table never depends on DuckDB's type guessing or the exact header spelling.
"""
import re
import sys
import time

import duckdb

sys.stdout.reconfigure(encoding="utf-8")  # box-drawing characters print correctly in any Windows terminal

CSV = "data/raw/complaints.csv"
DB = "data/complaints.duckdb"

# clean name -> (accepted header spellings, normalized; SQL type or None for text)
TARGETS = {
    "date_received":                ({"datereceived"}, "DATE"),
    "product":                      ({"product"}, None),
    "sub_product":                  ({"subproduct"}, None),
    "issue":                        ({"issue"}, None),
    "sub_issue":                    ({"subissue"}, None),
    "consumer_complaint_narrative": ({"consumercomplaintnarrative", "complaintnarrative",
                                      "consumercomplaintnarratives", "narrative"}, None),
    "company_public_response":      ({"companypublicresponse"}, None),
    "company":                      ({"company", "companyname"}, None),
    "state":                        ({"state"}, None),
    "zip_code":                     ({"zipcode", "zip"}, None),
    "tags":                         ({"tags"}, None),
    "consumer_consent_provided":    ({"consumerconsentprovided"}, None),
    "submitted_via":                ({"submittedvia"}, None),
    "date_sent_to_company":         ({"datesenttocompany"}, "DATE"),
    "company_response_to_consumer": ({"companyresponsetoconsumer"}, None),
    "timely_response":              ({"timelyresponse"}, None),
    "consumer_disputed":            ({"consumerdisputed"}, None),
    "complaint_id":                 ({"complaintid"}, "BIGINT"),
}
REQUIRED = {"date_received", "product", "company", "complaint_id"}


def norm(name: str) -> str:
    """'Consumer complaint narrative ' -> 'consumercomplaintnarrative'"""
    return re.sub(r"[^a-z0-9]", "", name.lower())


start = time.time()
con = duckdb.connect(DB)

# 1. Read the real header
src = f"read_csv('{CSV}', header = true, all_varchar = true)"
header = [row[0] for row in con.sql(f"DESCRIBE SELECT * FROM {src}").fetchall()]
print("Columns found in the CSV:")
for h in header:
    print(f"  {h!r}")

by_norm = {norm(h): h for h in header}

# 2. Build the SELECT list
select_parts, missing = [], []
for clean, (spellings, sql_type) in TARGETS.items():
    original = next((by_norm[s] for s in spellings if s in by_norm), None)
    if original is None:
        missing.append(clean)
        expr = "NULL" if sql_type is None else f"CAST(NULL AS {sql_type})"
    else:
        quoted = '"' + original.replace('"', '""') + '"'
        expr = quoted if sql_type is None else f"TRY_CAST({quoted} AS {sql_type})"
    select_parts.append(f"    {expr} AS {clean}")

if REQUIRED & set(missing):
    sys.exit(f"Required columns not found: {sorted(REQUIRED & set(missing))}. Check the header list above.")
if missing:
    print(f"\nWARNING: not found in this file, filled with NULL: {missing}")

# 3. Create the table
con.execute("CREATE OR REPLACE TABLE complaints AS\nSELECT\n" + ",\n".join(select_parts) + f"\nFROM {src}")

print(con.sql("""
    SELECT count(*)                     AS rows,
           count(DISTINCT complaint_id) AS distinct_ids,
           min(date_received)           AS first_date,
           max(date_received)           AS last_date
    FROM complaints
"""))
print(f"Loaded in {time.time() - start:.0f} s")
con.close()