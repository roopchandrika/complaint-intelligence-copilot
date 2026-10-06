"""Bronze layer: land the raw CSV exactly as received, plus ingestion metadata.

Rules for Bronze:
  - no business logic, no cleaning: every value stays TEXT, exactly as in the file
  - column names are only made SQL-friendly ("Sub-product" -> sub_product)
  - expected columns missing from the file are added as empty text, and logged
  - each row gets _ingested_at, _source_file and _batch_id
  - the same file always gets the same _batch_id, so re-running replaces it (idempotent)
"""
import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path

import duckdb

# Columns the CFPB documents. Silver depends on these names existing in Bronze.
EXPECTED = [
    "date_received", "product", "sub_product", "issue", "sub_issue",
    "consumer_complaint_narrative", "company_public_response", "company", "state",
    "zip_code", "tags", "consumer_consent_provided", "submitted_via",
    "date_sent_to_company", "company_response_to_consumer", "timely_response",
    "consumer_disputed", "complaint_id",
]


def snake(name: str) -> str:
    """'Sub-product' -> 'sub_product', 'Timely response?' -> 'timely_response'"""
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


def batch_id_for(path: Path) -> str:
    """Same file (name + size + modified time) -> same batch id."""
    st = path.stat()
    key = f"{path.name}|{st.st_size}|{int(st.st_mtime)}"
    return hashlib.sha1(key.encode()).hexdigest()[:12]


def build_bronze(con: duckdb.DuckDBPyConnection, csv_path: Path, snapshot_dir: Path | None) -> dict:
    src = csv_path.as_posix()
    reader = f"read_csv('{src}', header = true, all_varchar = true)"
    header = [r[0] for r in con.sql(f"DESCRIBE SELECT * FROM {reader}").fetchall()]

    by_snake = {snake(h): h for h in header}
    select, missing = [], []
    for col in EXPECTED:
        if col in by_snake:
            select.append('"' + by_snake[col].replace('"', '""') + f'" AS {col}')
        else:
            select.append(f"CAST(NULL AS VARCHAR) AS {col}")
            missing.append(col)
    extra = [h for s, h in by_snake.items() if s not in EXPECTED]

    batch = batch_id_for(csv_path)
    ingested_at = datetime.now(timezone.utc).replace(tzinfo=None)

    con.execute("CREATE SCHEMA IF NOT EXISTS bronze")
    con.execute(f"""
        CREATE OR REPLACE TABLE bronze.complaints_raw AS
        SELECT {", ".join(select)},
               CAST(? AS TIMESTAMP) AS _ingested_at,
               ?                    AS _source_file,
               ?                    AS _batch_id
        FROM {reader}
    """, [ingested_at, csv_path.name, batch])

    rows = con.sql("SELECT count(*) FROM bronze.complaints_raw").fetchone()[0]

    # Ingestion log: one row per batch (replaced if the same file is loaded again)
    con.execute("""
        CREATE TABLE IF NOT EXISTS bronze.ingest_log (
            batch_id VARCHAR PRIMARY KEY, source_file VARCHAR, ingested_at TIMESTAMP,
            row_count BIGINT, missing_columns VARCHAR, extra_columns VARCHAR)
    """)
    con.execute("DELETE FROM bronze.ingest_log WHERE batch_id = ?", [batch])
    con.execute("INSERT INTO bronze.ingest_log VALUES (?, ?, ?, ?, ?, ?)",
                [batch, csv_path.name, ingested_at, rows, ", ".join(missing), ", ".join(extra)])

    # Optional immutable snapshot as Parquet (compressed, typed, fast to re-read)
    if snapshot_dir is not None:
        out = snapshot_dir / f"batch={batch}"
        out.mkdir(parents=True, exist_ok=True)
        con.execute(f"COPY bronze.complaints_raw TO '{(out / 'complaints.parquet').as_posix()}' (FORMAT parquet)")

    return {"batch_id": batch, "rows": rows, "missing": missing, "extra": extra}
