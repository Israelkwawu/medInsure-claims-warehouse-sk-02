-- Business question: what did we pay per member per year for in-network care
-- versus out-of-network care?
-- network_status lives on the provider version that was effective on the
-- service date, so a later network change does not reclassify old claims.
-- Both rates share the same member denominator (members with at least one
-- claim that year), which keeps the comparison on one population.
CREATE OR REPLACE VIEW warehouse.q05_oon_cost_comparison AS
WITH member_year AS (
    SELECT
        d.year_number,
        m.member_id,
        SUM(CASE WHEN p.network_status = 'In-Network' THEN f.total_paid ELSE 0 END) AS in_network_paid,
        SUM(CASE WHEN p.network_status = 'Out-of-Network' THEN f.total_paid ELSE 0 END) AS out_of_network_paid
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_date AS d
        ON d.date_key = f.service_date_key
    JOIN warehouse.dim_member AS m
        ON m.member_key = f.member_key
    JOIN warehouse.dim_provider AS p
        ON p.provider_key = f.provider_key
    GROUP BY d.year_number, m.member_id
)
SELECT
    year_number,
    COUNT(*) AS members_with_claims,
    SUM(in_network_paid) AS in_network_paid,
    SUM(out_of_network_paid) AS out_of_network_paid,
    ROUND(SUM(in_network_paid) / NULLIF(COUNT(*), 0), 2) AS in_network_paid_per_member,
    ROUND(SUM(out_of_network_paid) / NULLIF(COUNT(*), 0), 2) AS out_of_network_paid_per_member
FROM member_year
GROUP BY year_number
ORDER BY year_number;

COMMENT ON VIEW warehouse.q05_oon_cost_comparison IS
    'In-network versus out-of-network paid amount per member per service year.';
