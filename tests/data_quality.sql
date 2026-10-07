-- Pass when failed / evaluated is at or under 1% (pass rate >= 99%).
WITH checks AS (
    SELECT
        1 AS sort_order,
        'fact_claim valid service date, processed date, member, and provider keys' AS check_name,
        COUNT(*) AS total_rows_evaluated,
        COUNT(*) FILTER (
            WHERE service_date.date_key IS NOT NULL
              AND service_date.date_key <> -1
              AND processed_date.date_key IS NOT NULL
              AND processed_date.date_key <> -1
              AND member.member_key IS NOT NULL
              AND member.member_key <> -1
              AND provider.provider_key IS NOT NULL
              AND provider.provider_key <> -1
        ) AS passed
    FROM warehouse.fact_claim AS claim
    LEFT JOIN warehouse.dim_date AS service_date
        ON service_date.date_key = claim.service_date_key
    LEFT JOIN warehouse.dim_date AS processed_date
        ON processed_date.date_key = claim.processed_date_key
    LEFT JOIN warehouse.dim_member AS member
        ON member.member_key = claim.member_key
    LEFT JOIN warehouse.dim_provider AS provider
        ON provider.provider_key = claim.provider_key

    UNION ALL

    SELECT
        2,
        'fact_claim total_paid within 5% of total_allowed',
        COUNT(*),
        COUNT(*) FILTER (WHERE NOT (total_paid > total_allowed * 1.05))
    FROM warehouse.fact_claim

    UNION ALL

    SELECT
        3,
        'dim_member one current row per member',
        COUNT(*),
        COUNT(*) FILTER (WHERE current_rows = 1)
    FROM (
        SELECT member_id, COUNT(*) FILTER (WHERE is_current) AS current_rows
        FROM warehouse.dim_member
        WHERE member_key <> -1
        GROUP BY member_id
    ) AS member_versions

    UNION ALL

    SELECT
        4,
        'dim_provider one current row per provider',
        COUNT(*),
        COUNT(*) FILTER (WHERE current_rows = 1)
    FROM (
        SELECT provider_id, COUNT(*) FILTER (WHERE is_current) AS current_rows
        FROM warehouse.dim_provider
        WHERE provider_key <> -1
        GROUP BY provider_id
    ) AS provider_versions

    UNION ALL

    SELECT
        5,
        'fact_claim_line claim_id exists on fact_claim',
        COUNT(*),
        COUNT(*) FILTER (WHERE header.claim_id IS NOT NULL)
    FROM warehouse.fact_claim_line AS line
    LEFT JOIN warehouse.fact_claim AS header
        ON header.claim_id = line.claim_id

    UNION ALL

    SELECT
        6,
        'fact_claim_line procedure code exists on dim_procedure',
        COUNT(*),
        COUNT(*) FILTER (WHERE procedure.procedure_key IS NOT NULL)
    FROM warehouse.fact_claim_line AS line
    LEFT JOIN warehouse.dim_procedure AS procedure
        ON procedure.procedure_code = line.source_procedure_code
       AND procedure.procedure_key <> -1

    UNION ALL

    SELECT
        7,
        'fact_claim service date on or after provider network_effective_date',
        COUNT(*),
        COUNT(*) FILTER (
            WHERE service_date.calendar_date >= provider.network_effective_date
        )
    FROM warehouse.fact_claim AS claim
    JOIN warehouse.dim_provider AS provider
        ON provider.provider_key = claim.provider_key
    JOIN warehouse.dim_date AS service_date
        ON service_date.date_key = claim.service_date_key
)
SELECT
    sort_order,
    check_name,
    total_rows_evaluated,
    passed,
    total_rows_evaluated - passed AS failed,
    ROUND(100.0 * passed / NULLIF(total_rows_evaluated, 0), 2) AS pass_rate,
    CASE
        WHEN total_rows_evaluated = 0 THEN 'FAIL'
        WHEN (total_rows_evaluated - passed)::numeric / total_rows_evaluated <= 0.01 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
INTO TEMP TABLE quality_results
FROM checks;

SELECT
    check_name,
    total_rows_evaluated,
    passed,
    failed,
    pass_rate,
    status
FROM quality_results
ORDER BY sort_order;

DO $$
DECLARE
    v_failed text;
BEGIN
    SELECT string_agg(check_name || ' (' || status || ')', ', ' ORDER BY sort_order)
    INTO v_failed
    FROM quality_results
    WHERE status <> 'PASS';

    IF v_failed IS NOT NULL THEN
        RAISE EXCEPTION 'Data-quality checks failed: %', v_failed;
    END IF;
END $$;
