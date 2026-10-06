# Data quality report

Generated 2026-10-06 12:28. Batch `4d05db8c6062` from `complaints.csv`.

## Reconciliation

| Check | Result |
|---|---|
| Bronze rows = Silver rows + rejects + duplicates removed | PASS |
| Silver has exactly one row per complaint_id | PASS |
| Gold monthly totals = Silver rows | PASS |
| Gold company totals = Silver rows with a company | PASS |
| Gold channel totals = Silver rows with days_to_send | PASS |

## Row counts per layer

| Layer | Rows |
|---|---|
| Bronze (raw, as received) | 18,191,687 |
| Rejected (quarantined with a reason) | 0 |
| Duplicate rows removed | 0 (from 0 complaint IDs that appeared more than once) |
| Silver (one row per complaint) | 18,191,687 |
| Gold: monthly_product_stats | 1,566 rows |
| Gold: company_scorecard | 8,123 rows |
| Gold: company_top_issues | 50,082 rows |
| Gold: channel_forwarding_stats | 6 rows |

## Rejected rows by reason

| reject_reason | rows |
|---|---|

## Source file

- Columns missing from the file (filled with NULL): consumer_complaint_narrative, consumer_consent_provided, consumer_disputed
- Extra columns not expected: none

## Completeness (Silver)

| column_name | pct_null |
|---|---|
| company | 0.0 |
| state (valid) | 0.347 |
| date_sent_to_company | 0.0 |
| is_timely | 0.0 |
| is_disputed | 100.0 |
| narrative | 100.0 |
| zip_code | 0.016 |

## Flagged rows (kept, not deleted)

| sent_before_received | invalid_state_code | future_date |
|---|---|---|
| 7,050 | 0 | 0 |

Invalid state codes found:

| state_raw | rows |
|---|---|

## Standardization

- Company names: 8,144 raw spellings became 8,123 companies (21 spellings merged into another; 8 spellings renamed by the curated seed map).
- Issues renamed to current CFPB wording via issue_map: 790,264 rows.
- Products not in product_map (kept as-is): 0.

Largest companies after cleaning (spot-check these for wrong merges):

| company | complaints | raw_name_variants | raw_spellings |
|---|---|---|---|
| TRANSUNION | 5,034,122 | 1 | TRANSUNION INTERMEDIATE HOLDINGS, INC. |
| EQUIFAX | 4,822,460 | 1 | EQUIFAX, INC. |
| EXPERIAN | 4,413,389 | 1 | Experian Information Solutions Inc. |
| BANK OF AMERICA | 187,800 | 1 | BANK OF AMERICA, NATIONAL ASSOCIATION |
| JPMORGAN CHASE | 176,918 | 1 | JPMORGAN CHASE & CO. |
| WELLS FARGO | 175,763 | 1 | WELLS FARGO & COMPANY |
| CAPITAL ONE | 173,482 | 1 | CAPITAL ONE FINANCIAL CORPORATION |
| CITIBANK | 142,729 | 1 | CITIBANK, N.A. |
| SYNCHRONY | 84,463 | 1 | SYNCHRONY FINANCIAL |
| RESURGENT CAPITAL SERVICES | 72,837 | 1 | Resurgent Capital Services L.P. |
| BLOCK | 71,604 | 1 | Block, Inc. |
| LEXISNEXIS | 69,030 | 1 | LEXISNEXIS |
| ENCORE CAPITAL | 68,237 | 1 | ENCORE CAPITAL GROUP INC. |
| PORTFOLIO RECOVERY ASSOCIATES | 66,807 | 1 | Portfolio Recovery Associates, LLC |
| AMERICAN EXPRESS | 60,532 | 1 | AMERICAN EXPRESS COMPANY |
| CBC COMPANIES | 58,938 | 1 | CBC Companies, Inc. |
| CL HOLDINGS | 54,998 | 1 | CL Holdings LLC |
| U.S. BANK | 50,116 | 1 | U.S. BANCORP |
| NAVY FEDERAL CREDIT UNION | 49,744 | 1 | NAVY FEDERAL CREDIT UNION |
| BREAD FINANCIAL | 49,327 | 1 | Bread Financial Holdings, Inc. |

## Companies flagged for checking (late on 99%+ of 500+ complaints)

| company | complaints | late_responses | late_pct |
|---|---|---|---|
| SERVICER UNDER CONTRACT WITH FEDERAL STUDENT AID | 7,544 | 7,544 | 100.0 |
| MOBILOANS | 910 | 910 | 100.0 |
| IPACS | 567 | 566 | 99.82 |

## Freshness

| first_date | last_date | rows_last_7_days |
|---|---|---|
| 2011-12-01 | 2026-10-05 | 88,672 |

## Step timings

| Step | Seconds |
|---|---|
| silver | 70.7 |
| gold | 2.6 |
