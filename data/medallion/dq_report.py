"""Data-quality report for the medallion layers. Writes data/medallion/DQ_REPORT.md.

The most important section is RECONCILIATION: every Bronze row must be accounted for
(kept in Silver, rejected with a reason, or removed as a duplicate), and Gold totals must
add back to Silver. If any check says FAIL, the numbers downstream cannot be trusted.
"""
from datetime import datetime
from pathlib import Path

import duckdb


def one(con, sql):
    return con.sql(sql).fetchone()[0]


def table_md(con, sql, limit=None) -> str:
    rel = con.sql(sql)
    cols = rel.columns
    rows = rel.fetchall()
    if limit:
        rows = rows[:limit]
    out = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        out.append("| " + " | ".join("" if v is None else (f"{v:,}" if isinstance(v, int) else str(v)) for v in r) + " |")
    return "\n".join(out)


def build_report(con: duckdb.DuckDBPyConnection, out_path: Path, timings: dict) -> list[tuple[str, bool]]:
    bronze = one(con, "SELECT count(*) FROM bronze.complaints_raw")
    silver = one(con, "SELECT count(*) FROM silver.complaints")
    rejects = one(con, "SELECT count(*) FROM silver.complaints_rejects")
    valid_rows = bronze - rejects
    duplicates_removed = valid_rows - silver
    dup_ids_in_bronze = one(con, """
        SELECT count(*) FROM (
            SELECT TRY_CAST(trim(complaint_id) AS BIGINT) AS id FROM bronze.complaints_raw
            WHERE TRY_CAST(trim(complaint_id) AS BIGINT) IS NOT NULL
              AND TRY_CAST(trim(date_received) AS DATE) IS NOT NULL
            GROUP BY id HAVING count(*) > 1)""")
    silver_dupes = one(con, "SELECT count(*) - count(DISTINCT complaint_id) FROM silver.complaints")
    gold_monthly = one(con, "SELECT sum(complaints) FROM gold.monthly_product_stats")
    gold_company = one(con, "SELECT sum(complaints) FROM gold.company_scorecard")
    silver_with_company = one(con, "SELECT count(*) FROM silver.complaints WHERE company IS NOT NULL")
    gold_channel = one(con, "SELECT sum(complaints) FROM gold.channel_forwarding_stats")
    silver_with_days = one(con, "SELECT count(*) FROM silver.complaints WHERE days_to_send IS NOT NULL")

    checks = [
        ("Bronze rows = Silver rows + rejects + duplicates removed",
         bronze == silver + rejects + duplicates_removed and duplicates_removed >= 0),
        ("Silver has exactly one row per complaint_id", silver_dupes == 0),
        ("Gold monthly totals = Silver rows", gold_monthly == silver),
        ("Gold company totals = Silver rows with a company", gold_company == silver_with_company),
        ("Gold channel totals = Silver rows with days_to_send", gold_channel == silver_with_days),
    ]

    log = con.sql("SELECT * FROM bronze.ingest_log ORDER BY ingested_at DESC LIMIT 1").fetchone()
    raw_names = one(con, "SELECT count(*) FROM silver.company_lookup")
    clean_names = one(con, "SELECT count(DISTINCT company) FROM silver.company_lookup")
    seed_mapped = one(con, "SELECT count(*) FROM silver.company_lookup WHERE mapped_by_seed")
    issues_mapped = one(con, "SELECT count(*) FROM silver.complaints WHERE issue <> issue_raw")
    products_unmapped = one(con, """SELECT count(DISTINCT product) FROM silver.complaints
                                    WHERE product NOT IN (SELECT product FROM silver.seed_product_map)""")

    lines = [
        "# Data quality report",
        "",
        f"Generated {datetime.now():%Y-%m-%d %H:%M}. Batch `{log[0]}` from `{log[1]}`.",
        "",
        "## Reconciliation",
        "",
        "| Check | Result |",
        "|---|---|",
        *[f"| {name} | {'PASS' if ok else '**FAIL**'} |" for name, ok in checks],
        "",
        "## Row counts per layer",
        "",
        "| Layer | Rows |",
        "|---|---|",
        f"| Bronze (raw, as received) | {bronze:,} |",
        f"| Rejected (quarantined with a reason) | {rejects:,} |",
        f"| Duplicate rows removed | {duplicates_removed:,} (from {dup_ids_in_bronze:,} complaint IDs that appeared more than once) |",
        f"| Silver (one row per complaint) | {silver:,} |",
        f"| Gold: monthly_product_stats | {one(con, 'SELECT count(*) FROM gold.monthly_product_stats'):,} rows |",
        f"| Gold: company_scorecard | {one(con, 'SELECT count(*) FROM gold.company_scorecard'):,} rows |",
        f"| Gold: company_top_issues | {one(con, 'SELECT count(*) FROM gold.company_top_issues'):,} rows |",
        f"| Gold: channel_forwarding_stats | {one(con, 'SELECT count(*) FROM gold.channel_forwarding_stats'):,} rows |",
        "",
        "## Rejected rows by reason",
        "",
        table_md(con, "SELECT reject_reason, count(*) AS rows FROM silver.complaints_rejects GROUP BY 1 ORDER BY 2 DESC"),
        "",
        "## Source file",
        "",
        f"- Columns missing from the file (filled with NULL): {log[4] or 'none'}",
        f"- Extra columns not expected: {log[5] or 'none'}",
        "",
        "## Completeness (Silver)",
        "",
        table_md(con, """
            SELECT 'company' AS column_name, round(100.0 * avg(CASE WHEN company IS NULL THEN 1 ELSE 0 END), 3) AS pct_null FROM silver.complaints
            UNION ALL SELECT 'state (valid)', round(100.0 * avg(CASE WHEN state IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
            UNION ALL SELECT 'date_sent_to_company', round(100.0 * avg(CASE WHEN date_sent_to_company IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
            UNION ALL SELECT 'is_timely', round(100.0 * avg(CASE WHEN is_timely IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
            UNION ALL SELECT 'is_disputed', round(100.0 * avg(CASE WHEN is_disputed IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
            UNION ALL SELECT 'narrative', round(100.0 * avg(CASE WHEN narrative IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
            UNION ALL SELECT 'zip_code', round(100.0 * avg(CASE WHEN zip_code IS NULL THEN 1 ELSE 0 END), 3) FROM silver.complaints
        """),
        "",
        "## Flagged rows (kept, not deleted)",
        "",
        table_md(con, """
            SELECT count(*) FILTER (WHERE dq_sent_before_received) AS sent_before_received,
                   count(*) FILTER (WHERE dq_invalid_state)        AS invalid_state_code,
                   count(*) FILTER (WHERE dq_future_date)          AS future_date
            FROM silver.complaints"""),
        "",
        "Invalid state codes found:",
        "",
        table_md(con, """SELECT state_raw, count(*) AS rows FROM silver.complaints
                         WHERE dq_invalid_state GROUP BY 1 ORDER BY 2 DESC LIMIT 15"""),
        "",
        "## Standardization",
        "",
        f"- Company names: {raw_names:,} raw spellings became {clean_names:,} companies "
        f"({raw_names - clean_names:,} spellings merged into another; {seed_mapped:,} spellings renamed by the curated seed map).",
        f"- Issues renamed to current CFPB wording via issue_map: {issues_mapped:,} rows.",
        f"- Products not in product_map (kept as-is): {products_unmapped:,}.",
        "",
        "Largest companies after cleaning (spot-check these for wrong merges):",
        "",
        table_md(con, """
            SELECT g.company, g.complaints, g.raw_name_variants,
                   string_agg(DISTINCT l.company_raw, ' | ') AS raw_spellings
            FROM gold.company_scorecard g
            JOIN silver.company_lookup l ON l.company = g.company
            GROUP BY g.company, g.complaints, g.raw_name_variants
            ORDER BY g.complaints DESC LIMIT 20"""),
        "",
        "## Companies flagged for checking (late on 99%+ of 500+ complaints)",
        "",
        table_md(con, """SELECT company, complaints, late_responses, late_pct FROM gold.company_scorecard
                         WHERE dq_check_all_late ORDER BY complaints DESC"""),
        "",
        "## Freshness",
        "",
        table_md(con, """SELECT min(date_received) AS first_date, max(date_received) AS last_date,
                                count(*) FILTER (WHERE date_received >= max_d - INTERVAL 7 DAY) AS rows_last_7_days
                         FROM silver.complaints, (SELECT max(date_received) AS max_d FROM silver.complaints)"""),
        "",
        "## Step timings",
        "",
        "| Step | Seconds |",
        "|---|---|",
        *[f"| {k} | {v:.1f} |" for k, v in timings.items()],
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return checks
