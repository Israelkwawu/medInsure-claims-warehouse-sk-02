-- Same 3-month moving average as warehouse.q06_monthly_volume, read from the
-- monthly summary instead of fact_claim.
CREATE OR REPLACE VIEW warehouse.q06_monthly_volume_mv AS
SELECT
    year_month,
    claim_count,
    total_paid,
    ROUND(
        AVG(claim_count) OVER (
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS claim_count_3_month_avg
FROM warehouse.mv_monthly_claim_volume
ORDER BY month_start;

COMMENT ON VIEW warehouse.q06_monthly_volume_mv IS
    'Query 6 answered from mv_monthly_claim_volume.';
