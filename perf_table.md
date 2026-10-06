| Query | Question | Before | After | Speedup | Plan before | Plan after |
|---|---|---|---|---|---|---|
| Q1 | How many complaints does each product receive per month? | 33,654 ms | 2,623 ms | 13x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_product_date on complaints |
| Q2 | Is each product getting better or worse month over month? | 5,958 ms | 2,156 ms | 3x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_product_date on complaints |
| Q3 | What are the top 5 issues for each of the 10 most-complained-about companies? | 12,073 ms | - |  | Seq Scan on complaints; Parallel Seq Scan on complaints | - |
| Q4 | What is the running total of complaints per product during 2025? | 8,866 ms | 521 ms | 17x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_product_date on complaints |
| Q5 | Which companies respond late most often (at least 500 complaints)? | 2,697 ms | 27,273 ms | 0x | Parallel Seq Scan on complaints | Parallel Seq Scan on complaints |
| Q6 | What share of each month's complaints does each product represent? | 9,070 ms | 2,329 ms | 4x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_product_date on complaints |
| Q7 | What is the 3-month moving average of mortgage complaints? | 27,451 ms | 94 ms | 292x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_product_date on complaints |
| Q8 | How many days does the CFPB take to forward complaints, by channel? | 158,895 ms | 132,671 ms | 1x | Seq Scan on complaints | Seq Scan on complaints |
| P1 | (API lookup): What is the full record for one complaint? | 26,266 ms | 2.4 ms | 10,809x | Parallel Seq Scan on complaints | Index Scan using idx_complaints_id on complaints |
| P2 | (API lookup): What were Wells Fargo's top issues in 2025? | 4,505 ms | 34 ms | 134x | Parallel Seq Scan on complaints | Bitmap Heap Scan on complaints; Bitmap Index Scan on idx_complaints_company_date |
| P3a | How many complaints arrived on 2025-03-03? (NOT sargable: function on the column) | 3,654 ms | 2,424 ms | 2x | Parallel Seq Scan on complaints | Parallel Index Only Scan using idx_complaints_date on complaints |
| P3b | How many complaints arrived on 2025-03-03? (sargable: bare column vs a constant) | 1,107 ms | 2.9 ms | 380x | Parallel Seq Scan on complaints | Index Only Scan using idx_complaints_date on complaints |
| Q2-MV | Same question as Q2, answered from the pre-aggregated materialized view (exists only after fixes.sql) | 5,958 ms | 14 ms | 431x | Parallel Seq Scan on complaints | Seq Scan on mv_monthly_product |
