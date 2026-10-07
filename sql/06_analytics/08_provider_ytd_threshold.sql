-- Business question: what is each provider's year-to-date paid amount, and on
-- which date did that provider cross $1,000,000?
-- The cumulative sum is computed from fact_claim and the service-date role of
-- dim_date. Contract review no longer has to replay the claim ledger.
CREATE OR REPLACE VIEW warehouse.q08_provider_ytd_threshold AS
WITH daily AS (
    SELECT
        cur.provider_id,
        cur.provider_name,
        d.year_number,
        d.calendar_date,
        SUM(f.total_paid) AS paid_on_day
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_provider AS ver
        ON ver.provider_key = f.provider_key
    JOIN warehouse.dim_provider AS cur
        ON cur.provider_id = ver.provider_id
       AND cur.is_current
    JOIN warehouse.dim_date AS d
        ON d.date_key = f.service_date_key
    GROUP BY cur.provider_id, cur.provider_name, d.year_number, d.calendar_date
),
running AS (
    SELECT
        daily.provider_id,
        daily.provider_name,
        daily.year_number,
        daily.calendar_date,
        daily.paid_on_day,
        SUM(daily.paid_on_day) OVER (
            PARTITION BY daily.provider_id, daily.year_number
            ORDER BY daily.calendar_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS ytd_paid
    FROM daily
)
SELECT
    running.provider_id,
    running.provider_name,
    running.year_number,
    MAX(running.ytd_paid) AS ytd_paid,
    MIN(running.calendar_date) FILTER (
        WHERE running.ytd_paid >= 1000000
          AND running.ytd_paid - running.paid_on_day < 1000000
    ) AS crossed_one_million_on,
    (
        MIN(running.calendar_date) FILTER (
            WHERE running.ytd_paid >= 1000000
              AND running.ytd_paid - running.paid_on_day < 1000000
        ) IS NOT NULL
    ) AS crossed_one_million
FROM running
GROUP BY running.provider_id, running.provider_name, running.year_number
ORDER BY running.year_number, ytd_paid DESC;

COMMENT ON VIEW warehouse.q08_provider_ytd_threshold IS
    'Provider year-to-date paid amount and the date the provider crossed $1M.';
