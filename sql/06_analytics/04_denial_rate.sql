-- Business question: where do denials concentrate, by the specialty on the
-- claim and by claim type?
-- provider_key points at the specialty version in effect on the service date.
-- A current-only provider table would score old claims with today's specialty.
CREATE OR REPLACE VIEW warehouse.q04_denial_rate AS
SELECT
    p.specialty,
    f.claim_type,
    COUNT(*) AS claims,
    SUM(CASE WHEN f.claim_status = 'Denied' THEN 1 ELSE 0 END) AS denied_claims,
    ROUND(
        100.0 * SUM(CASE WHEN f.claim_status = 'Denied' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS denial_rate_pct
FROM warehouse.fact_claim AS f
JOIN warehouse.dim_provider AS p
    ON p.provider_key = f.provider_key
GROUP BY p.specialty, f.claim_type
ORDER BY denial_rate_pct DESC, claims DESC;

COMMENT ON VIEW warehouse.q04_denial_rate IS
    'Denial rate by provider specialty and claim type.';
