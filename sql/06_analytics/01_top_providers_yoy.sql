-- Business question: which 20 providers were paid the most in the latest service
-- year, and how does that compare with the immediately previous year?
-- The warehouse makes this possible because fact_claim is already at claim grain
-- with a provider surrogate, and dim_date supplies the service year without
-- scanning the OLTP header/line join. LAG compares years on the natural provider
-- id, so a mid-year SCD version does not split one provider into two.
CREATE OR REPLACE VIEW warehouse.q01_top_providers_yoy AS
WITH provider_year AS (
    SELECT
        cur.provider_id,
        cur.provider_name,
        cur.specialty,
        d.year_number,
        SUM(f.total_paid) AS total_paid
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_provider AS ver
        ON ver.provider_key = f.provider_key
    JOIN warehouse.dim_provider AS cur
        ON cur.provider_id = ver.provider_id
       AND cur.is_current
    JOIN warehouse.dim_date AS d
        ON d.date_key = f.service_date_key
    GROUP BY cur.provider_id, cur.provider_name, cur.specialty, d.year_number
),
with_lag AS (
    SELECT
        provider_year.provider_id,
        provider_year.provider_name,
        provider_year.specialty,
        provider_year.year_number,
        provider_year.total_paid,
        LAG(provider_year.year_number) OVER (
            PARTITION BY provider_year.provider_id
            ORDER BY provider_year.year_number
        ) AS prior_year_number,
        LAG(provider_year.total_paid) OVER (
            PARTITION BY provider_year.provider_id
            ORDER BY provider_year.year_number
        ) AS prior_year_paid
    FROM provider_year
),
latest_year AS (
    SELECT
        with_lag.provider_id,
        with_lag.provider_name,
        with_lag.specialty,
        with_lag.year_number,
        with_lag.total_paid,
        CASE
            WHEN with_lag.prior_year_number = with_lag.year_number - 1 THEN with_lag.prior_year_paid
        END AS prior_year_paid
    FROM with_lag
    WHERE with_lag.year_number = (SELECT MAX(year_number) FROM with_lag)
)
SELECT
    ROW_NUMBER() OVER (ORDER BY latest_year.total_paid DESC, latest_year.provider_id) AS provider_rank,
    latest_year.provider_id,
    latest_year.provider_name,
    latest_year.specialty,
    latest_year.year_number,
    latest_year.total_paid,
    latest_year.prior_year_paid,
    ROUND(
        100.0 * (latest_year.total_paid - latest_year.prior_year_paid)
        / NULLIF(latest_year.prior_year_paid, 0),
        1
    ) AS yoy_change_pct
FROM latest_year
ORDER BY latest_year.total_paid DESC, latest_year.provider_id
LIMIT 20;

COMMENT ON VIEW warehouse.q01_top_providers_yoy IS
    'Top 20 providers by paid amount in the latest service year, with prior-year comparison via LAG.';
