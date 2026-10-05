import duckdb

n = duckdb.sql(
    "SELECT count(*) FROM read_csv_auto('data/raw/complaints.csv')"
).fetchone()[0]
print(f"{n:,} rows")

print(duckdb.sql("""
    SELECT count(*)                     AS total_rows,
           count(DISTINCT "Complaint ID") AS distinct_ids,
           min("Date received")         AS first_date,
           max("Date received")         AS last_date
    FROM read_csv_auto('data/raw/complaints.csv')
"""))