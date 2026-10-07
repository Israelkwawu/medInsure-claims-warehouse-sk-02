-- Full refresh. The summary is one row per month, so the lock is short.
-- After the first population, REFRESH MATERIALIZED VIEW CONCURRENTLY is safe
-- because uq_mv_monthly_claim_volume_year_month is unique.
CREATE OR REPLACE PROCEDURE warehouse.refresh_monthly_claim_volume()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW warehouse.mv_monthly_claim_volume;
END;
$$;
