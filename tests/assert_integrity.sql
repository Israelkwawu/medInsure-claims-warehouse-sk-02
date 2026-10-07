-- Structural assertions for the loaded warehouse. Any inserted row raises
-- at the bottom, which makes this script fail under ON_ERROR_STOP.
CREATE TEMP TABLE test_failures (
    test_name text PRIMARY KEY,
    detail text NOT NULL
);

INSERT INTO test_failures (test_name, detail)
SELECT
    'dim_date covers 2020-2030',
    'expected 4018 calendar days, found ' || COUNT(*)::text
FROM warehouse.dim_date
WHERE calendar_date BETWEEN DATE '2020-01-01' AND DATE '2030-12-31'
HAVING COUNT(*) <> 4018
    OR MIN(calendar_date) <> DATE '2020-01-01'
    OR MAX(calendar_date) <> DATE '2030-12-31';

INSERT INTO test_failures (test_name, detail)
SELECT 'unknown dimension row ' || dimension_name, 'missing surrogate -1'
FROM (
    SELECT 'dim_date' AS dimension_name, COUNT(*) AS present
    FROM warehouse.dim_date WHERE date_key = -1
    UNION ALL
    SELECT 'dim_plan', COUNT(*) FROM warehouse.dim_plan WHERE plan_key = -1
    UNION ALL
    SELECT 'dim_member', COUNT(*) FROM warehouse.dim_member WHERE member_key = -1
    UNION ALL
    SELECT 'dim_provider', COUNT(*) FROM warehouse.dim_provider WHERE provider_key = -1
    UNION ALL
    SELECT 'dim_diagnosis', COUNT(*) FROM warehouse.dim_diagnosis WHERE diagnosis_key = -1
    UNION ALL
    SELECT 'dim_procedure', COUNT(*) FROM warehouse.dim_procedure WHERE procedure_key = -1
) AS unknown_rows
WHERE present <> 1;

INSERT INTO test_failures (test_name, detail)
SELECT
    'dim_member has a second SCD version',
    'no member has more than one version'
WHERE NOT EXISTS (
    SELECT 1
    FROM warehouse.dim_member
    WHERE member_key <> -1
    GROUP BY member_id
    HAVING COUNT(*) > 1
);

INSERT INTO test_failures (test_name, detail)
SELECT
    'dim_provider has a second SCD version',
    'no provider has more than one version'
WHERE NOT EXISTS (
    SELECT 1
    FROM warehouse.dim_provider
    WHERE provider_key <> -1
    GROUP BY provider_id
    HAVING COUNT(*) > 1
);

INSERT INTO test_failures (test_name, detail)
SELECT 'dim_member overlapping versions', 'member_id ' || a.member_id::text
FROM warehouse.dim_member AS a
JOIN warehouse.dim_member AS b
    ON a.member_id = b.member_id
   AND a.member_key < b.member_key
   AND a.effective_start <= b.effective_end
   AND b.effective_start <= a.effective_end
LIMIT 1;

INSERT INTO test_failures (test_name, detail)
SELECT 'dim_provider overlapping versions', 'provider_id ' || a.provider_id::text
FROM warehouse.dim_provider AS a
JOIN warehouse.dim_provider AS b
    ON a.provider_id = b.provider_id
   AND a.provider_key < b.provider_key
   AND a.effective_start <= b.effective_end
   AND b.effective_start <= a.effective_end
LIMIT 1;

INSERT INTO test_failures (test_name, detail)
SELECT 'dim_member multiple current rows', 'member_id ' || member_id::text
FROM warehouse.dim_member
WHERE is_current
GROUP BY member_id
HAVING COUNT(*) > 1
LIMIT 1;

INSERT INTO test_failures (test_name, detail)
SELECT 'dim_provider multiple current rows', 'provider_id ' || provider_id::text
FROM warehouse.dim_provider
WHERE is_current
GROUP BY provider_id
HAVING COUNT(*) > 1
LIMIT 1;

INSERT INTO test_failures (test_name, detail)
SELECT
    'fact_claim service date inside member version',
    COUNT(*)::text || ' claims fall outside the member version'
FROM warehouse.fact_claim AS claim
JOIN warehouse.dim_member AS member
    ON member.member_key = claim.member_key
JOIN warehouse.dim_date AS service_date
    ON service_date.date_key = claim.service_date_key
WHERE service_date.calendar_date NOT BETWEEN member.effective_start AND member.effective_end
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'fact_claim service date inside provider version',
    COUNT(*)::text || ' claims fall outside the provider version'
FROM warehouse.fact_claim AS claim
JOIN warehouse.dim_provider AS provider
    ON provider.provider_key = claim.provider_key
JOIN warehouse.dim_date AS service_date
    ON service_date.date_key = claim.service_date_key
WHERE service_date.calendar_date NOT BETWEEN provider.effective_start AND provider.effective_end
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'fact_claim line_count matches fact_claim_line',
    COUNT(*)::text || ' headers disagree with their lines'
FROM warehouse.fact_claim AS claim
LEFT JOIN (
    SELECT claim_id, COUNT(*) AS line_rows
    FROM warehouse.fact_claim_line
    GROUP BY claim_id
) AS lines ON lines.claim_id = claim.claim_id
WHERE claim.line_count IS DISTINCT FROM COALESCE(lines.line_rows, 0)
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'fact_claim totals match summed lines',
    COUNT(*)::text || ' headers disagree with line amounts'
FROM warehouse.fact_claim AS claim
JOIN (
    SELECT
        claim_id,
        SUM(billed_amount) AS billed,
        SUM(allowed_amount) AS allowed,
        SUM(paid_amount) AS paid
    FROM warehouse.fact_claim_line
    GROUP BY claim_id
) AS lines ON lines.claim_id = claim.claim_id
WHERE claim.total_billed IS DISTINCT FROM lines.billed
   OR claim.total_allowed IS DISTINCT FROM lines.allowed
   OR claim.total_paid IS DISTINCT FROM lines.paid
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'dead letter has both reject reasons',
    'found ' || COUNT(DISTINCT reject_reason)::text || ' reason(s)'
FROM audit.etl_dead_letter
WHERE pipeline_name = 'fact_claim'
  AND reject_reason IN (
      'member not found for service date',
      'provider not found for service date'
  )
HAVING COUNT(DISTINCT reject_reason) <> 2;

INSERT INTO test_failures (test_name, detail)
SELECT
    'dead-letter claims stayed out of fact_claim',
    COUNT(*)::text || ' rejected claims were loaded'
FROM audit.etl_dead_letter AS rejected
JOIN warehouse.fact_claim AS claim
    ON claim.claim_id::text = rejected.source_key
WHERE rejected.pipeline_name = 'fact_claim'
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT 'q01 returns at most 20 providers', COUNT(*)::text || ' rows'
FROM warehouse.q01_top_providers_yoy
HAVING COUNT(*) = 0 OR COUNT(*) > 20;

INSERT INTO test_failures (test_name, detail)
SELECT 'q02 spend rank starts at 1', 'minimum rank ' || MIN(spend_rank)::text
FROM warehouse.q02_diagnosis_category_spend
HAVING MIN(spend_rank) IS DISTINCT FROM 1;

INSERT INTO test_failures (test_name, detail)
SELECT
    'q04 denial rate stays between 0 and 100',
    COUNT(*)::text || ' rows out of range'
FROM warehouse.q04_denial_rate
WHERE denial_rate_pct < 0 OR denial_rate_pct > 100
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'q06 base monthly counts match the materialized view',
    COUNT(*)::text || ' months differ'
FROM (
    SELECT year_month, claim_count, total_paid
    FROM warehouse.q06_monthly_volume
    EXCEPT
    SELECT year_month, claim_count, total_paid
    FROM warehouse.mv_monthly_claim_volume
) AS difference
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'q06 three-month average',
    COUNT(*)::text || ' months disagree with the window'
FROM (
    SELECT
        claim_count_3_month_avg,
        ROUND(AVG(claim_count) OVER (
            ORDER BY year_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2) AS expected_avg,
        ROW_NUMBER() OVER (ORDER BY year_month) AS month_number
    FROM warehouse.q06_monthly_volume
) AS moving
WHERE month_number >= 3
  AND claim_count_3_month_avg IS DISTINCT FROM expected_avg
HAVING COUNT(*) > 0;

INSERT INTO test_failures (test_name, detail)
SELECT
    'q08 threshold flag matches the crossing date',
    COUNT(*)::text || ' provider-years disagree'
FROM warehouse.q08_provider_ytd_threshold
WHERE crossed_one_million IS DISTINCT FROM (crossed_one_million_on IS NOT NULL)
   OR ytd_paid < 0
HAVING COUNT(*) > 0;

DO $$
DECLARE
    v_count integer;
    v_msg text;
BEGIN
    SELECT COUNT(*), string_agg(test_name || ': ' || detail, E'\n' ORDER BY test_name)
    INTO v_count, v_msg
    FROM test_failures;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Integrity tests failed (%):%', v_count, E'\n' || v_msg;
    END IF;

    RAISE NOTICE 'Integrity tests passed';
END $$;
