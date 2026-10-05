from jd.jd_scorer import score_posting, label

def test_sales_role_flagged():
    s, _ = score_posting("Carry a quota. OTE $250k. Partner with Account Executives on demos.")
    assert label(s) == "SALES-DISGUISED"

def test_engineering_role():
    s, _ = score_posting("Build and deploy production RAG systems in Python on Kubernetes, end-to-end.",
                         reports_to="Head of Forward Deployed Engineering")
    assert label(s) == "engineering"
