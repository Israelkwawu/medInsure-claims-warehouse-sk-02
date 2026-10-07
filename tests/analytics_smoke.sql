-- Each analytic view must return at least one row. An empty view means the
-- query failed to answer the business question on the loaded warehouse.
SELECT query_name, result_rows
INTO TEMP TABLE analytics_smoke
FROM (
    SELECT 'q01_top_providers_yoy' AS query_name, COUNT(*) AS result_rows
    FROM warehouse.q01_top_providers_yoy
    UNION ALL
    SELECT 'q02_diagnosis_category_spend', COUNT(*)
    FROM warehouse.q02_diagnosis_category_spend
    UNION ALL
    SELECT 'q03_member_utilization', COUNT(*)
    FROM warehouse.q03_member_utilization
    UNION ALL
    SELECT 'q04_denial_rate', COUNT(*)
    FROM warehouse.q04_denial_rate
    UNION ALL
    SELECT 'q05_oon_cost_comparison', COUNT(*)
    FROM warehouse.q05_oon_cost_comparison
    UNION ALL
    SELECT 'q06_monthly_volume', COUNT(*)
    FROM warehouse.q06_monthly_volume
    UNION ALL
    SELECT 'q06_monthly_volume_mv', COUNT(*)
    FROM warehouse.q06_monthly_volume_mv
    UNION ALL
    SELECT 'q07_member_cohort', COUNT(*)
    FROM warehouse.q07_member_cohort
    UNION ALL
    SELECT 'q08_provider_ytd_threshold', COUNT(*)
    FROM warehouse.q08_provider_ytd_threshold
) AS results
ORDER BY query_name;

SELECT query_name, result_rows
FROM analytics_smoke
ORDER BY query_name;

DO $$
DECLARE
    v_empty text;
BEGIN
    SELECT string_agg(query_name, ', ' ORDER BY query_name)
    INTO v_empty
    FROM analytics_smoke
    WHERE result_rows = 0;

    IF v_empty IS NOT NULL THEN
        RAISE EXCEPTION 'Analytic views returned no rows: %', v_empty;
    END IF;
END $$;
