# Data assumptions and cleaning decisions

Every judgment call made while cleaning the CFPB complaints data, why it was made, and how
many rows it affects. Numbers come from the snapshot downloaded on 2026-10-05
(18,191,687 complaints, 2011-12-01 to 2026-10-05). Code: `data/dbt_complaints/`.

## Source

| # | Assumption | Why | Impact |
|---|---|---|---|
| 1 | The CFPB file is a daily snapshot; results are tied to the download date. | The CFPB adds complaints every day. | Snapshot date recorded: 2026-10-05. |
| 2 | Three documented columns are missing from this file: consumer complaint narrative, consumer consent provided, consumer disputed. They are kept as empty columns. | The pipeline must not break when the file layout changes. | 100% empty. Narratives are needed for RAG later and must come from another download. |
| 3 | All raw values are stored as text in Bronze and typed in staging. | Automatic type guessing turned "Timely response?" into true/false and "NA" into NULL on earlier days. | 0 rows lost to typing. |

## Grain and keys

| # | Decision | Why | Impact |
|---|---|---|---|
| 4 | Grain of the cleaned table and the fact table: one row per `complaint_id`. | It is the CFPB's unique business key. | 18,191,687 rows; tested `unique` + `not_null`. |
| 5 | Duplicate complaint IDs: keep the copy with the latest `date_sent_to_company`, then the latest ingestion. | The latest copy is the most complete. | 0 duplicates in this snapshot; the rule stays for future reloads. |
| 6 | Rows without a valid complaint ID or `date_received` go to `stg_complaints_rejects` with a reason. They are never silently dropped. | They cannot be placed in time or deduplicated. | 0 rows in this snapshot. |
| 7 | Dimensions use surrogate keys; key `-1` means Unknown. | Facts with a missing value still join and still count in totals. | Unknown state: 0.35% of complaints. |

## Text standardization

| # | Decision | Why | Impact |
|---|---|---|---|
| 8 | Empty text is treated as NULL. Descriptive columns use 'N/A' or 'Unknown' instead of NULL. | CSV files write "missing" as empty text; labels keep group-bys readable. | All text columns. |
| 9 | Products map to a stable `product_group` (seed `product_map`). Original names are kept. | The CFPB renamed products on 2017-04-24 and 2023-08-24. | 21 product names → 11 groups. 3 names for credit reporting become one group. |
| 10 | Old issue names map to current wording (seed `issue_map`). Original kept as `issue_raw`. | Each mapping is backed by data: the old name stops on 2017-04-21/22 and the new one starts on 2017-04-24. | 790,264 rows renamed. |
| 11 | State codes are checked against a list of 50 states, DC, territories and military codes. Full names the CFPB sometimes writes are mapped to codes (seed `state_alias`). Invalid codes become NULL and are flagged. | Only 51 of the 63 raw values are states + DC. | 1,528 rows had "UNITED STATES MINOR OUTLYING ISLANDS" → mapped to UM. 0 invalid codes left. |

## Company names

| # | Decision | Why | Impact |
|---|---|---|---|
| 12 | Clean the text: upper case, apostrophes removed, other punctuation to spaces, leading "THE" removed. | Same company, different typing. | "IPAC'S Inc." → IPACS. |
| 13 | Legal-form suffixes (Inc, LLC, Corp, Co, N.A., L.P. ...) are removed from the END of a name only. | The first version removed "CORP" from the middle and merged "Credit Corp Solutions" into "Credit Solutions". | Fixed after manual review. |
| 14 | HOLDINGS / GROUP are removed only if at least two words remain. | "CL Holdings LLC" became "CL". | "CL HOLDINGS" kept. |
| 15 | Spellings merge only when they share ONE legal form (Inc = Incorporated, Corp = Corporation, N.A. = National Association). A spelling with no legal form may join. Different legal forms stay separate. | Generic names with different legal forms are often different companies: "Independent Bank Corp." (MA) vs "Independent Bank Group, Inc." (TX). | 8,144 raw spellings → 8,123 companies. 21 merges, all reviewed by hand. |
| 16 | No automatic fuzzy merging. Fuzzy matching only suggests pairs for a person to review; approved merges go into seed `company_map`. | In a regulated setting, merging two different companies is worse than leaving two spellings apart. On test data, "First National Bank of Omaha" and "...of Pennsylvania" scored 88% similar. | Seed `company_map`: 10 human-approved entries (e.g. Experian Information Solutions → EXPERIAN). |

## Measures and flags

| # | Decision | Why | Impact |
|---|---|---|---|
| 17 | `is_timely`: Yes → true, No → false, anything else → NULL. Percentages are computed from parts (late / responses known), never by averaging percentages. | Averaging per-company percentages gave 74.22% vs the real 99.55% (Day 5). | Applies to every timeliness metric. |
| 18 | `is_disputed` NULL means "not collected", not "No". | The column is missing from this file (and was retired by the CFPB). | 100% NULL; not used in metrics. |
| 19 | Complaints sent to the company before they were received are kept and flagged (`dq_sent_before_received`). | Likely a source data error; deleting would hide it. | 7,050 rows flagged. |
| 20 | Companies late on 99%+ of 500+ complaints are flagged (`dq_check_all_late`) for checking before anyone reports them. | 100% late is more likely a recording quirk than reality. | 3 companies, e.g. "Servicer under contract with Federal Student Aid": 7,544 complaints, 100% late. |
| 21 | The most recent month is flagged as partial (`is_partial_month`) and should be excluded from trends. | On Day 2, comparing 5 days of October with all of September showed a false 95–99% drop. | 1 month flagged at any time. |

## How these are enforced

- dbt tests: `unique`/`not_null` on every key, `relationships` from the fact to every dimension,
  accepted values and ranges, and singular tests for reconciliation (Bronze = clean + rejects +
  duplicates; every summary table adds back to the clean table), no merges across legal forms,
  and only the latest month flagged as partial.
- A unit test fixes the company rules on example names (Wells Fargo, Credit Corp Solutions,
  Independent Bank, CL Holdings, IPAC'S, COSTCO, Bank of the West, TransUnion).
- `dbt build` stops everything downstream when a test fails.
