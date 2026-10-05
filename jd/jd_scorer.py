"""Score FDE job postings: positive = engineering role, negative = sales-disguised."""
import argparse
import re
from pathlib import Path
import pandas as pd
# (pattern, weight). Positive = engineering signal, negative = sales signal.
SIGNALS: list[tuple[str, int]] = [
    # engineering signals
    (r"\bproduction\b", 3),
    (r"\b(build|ship|deploy)(s|ing)?\b", 2),
    (r"\bend[- ]to[- ]end\b", 2),
    (r"\b(python|sql|typescript|go|java)\b", 1),
    (r"\b(kubernetes|docker|terraform|aws|gcp|azure)\b", 1),
    (r"\b(rag|llms?|agents?|evals?|mcp)\b", 1),
    (r"\b(data pipelines?|etl|dbt)\b", 1),
    # sales signals
    (r"\bquota\b", -5),
    (r"\bOTE\b", -5),
    (r"\bcommission\b", -4),
    (r"\b(pre-?sales)\b", -4),
    (r"\b(close deals?|drive revenue|pipeline generation)\b", -3),
    (r"\baccount executives?\b", -2),
    (r"\b(demos?|presentations?)\b", -1),
     (r"\b(rfp|rfi)s?\b", -2),
]
REPORTS_TO_SALES = re.compile(r"\b(sales|revenue|go[- ]to[- ]market|gtm)\b", re.I)
REPORTS_TO_ENG = re.compile(r"\b(engineering|cto|forward deployed)\b", re.I)
def score_posting(description: str, reports_to: str = "", comp_text: str = "") -> tuple[int, list[str]]:
    text = f"{description} {comp_text}"
    score, hits = 0, []
    for pattern, weight in SIGNALS:
        # OTE must stay case-sensitive to avoid matching "note"/"vote" fragments
        flags = 0 if pattern == r"\bOTE\b" else re.IGNORECASE
        n = len(re.findall(pattern, text, flags=flags))
        if n:
            contribution = weight * min(n, 3)  # cap repeats so one word can't dominate
            score += contribution
            hits.append(f"{pattern}:{contribution:+d}")
    if REPORTS_TO_SALES.search(reports_to or ""):
        score -= 6
        hits.append("reports_to_sales:-6")
    elif REPORTS_TO_ENG.search(reports_to or ""):
        score += 4
        hits.append("reports_to_eng:+4")
    return score, hits
def label(score: int) -> str:
    if score >= 8:
        return "engineering"
    if score <= -3:
        return "SALES-DISGUISED"
    return "mixed - read carefully"
def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path, nargs="?", 
default=Path(__file__).with_name("postings.csv"))
    args = parser.parse_args()
    df = pd.read_csv(args.csv).fillna("")
    results = df.apply(
        lambda r: score_posting(r["description"], r["reports_to"], r["comp_text"]), axis=1
    )
    df["score"] = [s for s, _ in results]
    df["evidence"] = ["; ".join(h) for _, h in results]
    df["label"] = df["score"].map(label)
    ranked = df.sort_values("score", ascending=False)
    print(ranked[["company", "title", "score", "label"]].to_string(index=False))
    ranked.to_csv(args.csv.with_name("postings_scored.csv"), index=False)
if __name__ == "__main__":
    main()