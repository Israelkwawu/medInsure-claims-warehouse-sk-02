-- Pre-aggregate for query 6. The moving average stays in the view that reads
-- this summary, so a refresh does not have to recompute the window from facts.
DROP MATERIALIZED VIEW IF EXISTS warehouse.mv_monthly_claim_volume CASCADE;

CREATE MATERIALIZED VIEW warehouse.mv_monthly_claim_volume AS
SELECT
    d.year_month,
    MIN(d.calendar_date) AS month_start,
    COUNT(*) AS claim_count,
    SUM(f.total_paid) AS total_paid
FROM warehouse.fact_claim AS f
JOIN warehouse.dim_date AS d
    ON d.date_key = f.service_date_key
GROUP BY d.year_month
WITH DATA;

CREATE UNIQUE INDEX uq_mv_monthly_claim_volume_year_month
    ON warehouse.mv_monthly_claim_volume (year_month);

COMMENT ON MATERIALIZED VIEW warehouse.mv_monthly_claim_volume IS
    'One row per service month. Refresh after each fact_claim load. Unique year_month allows REFRESH MATERIALIZED VIEW CONCURRENTLY.';
