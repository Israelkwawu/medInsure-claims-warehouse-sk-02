-- Business question: which ICD-10 categories account for paid claims spend, and
-- in what order?
-- dim_diagnosis carries the category hierarchy, so the fact stays at claim grain
-- and the ranking does not require a self-join back to the OLTP code table.
CREATE OR REPLACE VIEW warehouse.q02_diagnosis_category_spend AS
SELECT
    dx.category_name,
    COUNT(*) AS paid_claims,
    SUM(f.total_paid) AS total_paid,
    RANK() OVER (ORDER BY SUM(f.total_paid) DESC) AS spend_rank
FROM warehouse.fact_claim AS f
JOIN warehouse.dim_diagnosis AS dx
    ON dx.diagnosis_key = f.primary_diagnosis_key
WHERE f.claim_status = 'Paid'
  AND dx.diagnosis_key <> -1
GROUP BY dx.category_name
ORDER BY spend_rank, dx.category_name;

COMMENT ON VIEW warehouse.q02_diagnosis_category_spend IS
    'Paid amount by ICD-10 category, ranked by spend.';
