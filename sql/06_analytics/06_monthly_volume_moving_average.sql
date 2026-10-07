-- Business question: is monthly claim volume rising, once a 3-month moving
-- average takes the noise out?
-- dim_date.year_month is the bucket. The fact does not store a date string,
-- and the window can run over one row per month instead of one row per claim
-- after the aggregate. Service month is the volume trend; processed month is
-- the same query with processed_date_key.
CREATE OR REPLACE VIEW warehouse.q06_monthly_volume AS
WITH monthly AS (
    SELECT
        d.year_month,
        MIN(d.calendar_date) AS month_start,
        COUNT(*) AS claim_count,
        SUM(f.total_paid) AS total_paid
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_date AS d
        ON d.date_key = f.service_date_key
    GROUP BY d.year_month
)
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
FROM monthly
ORDER BY month_start;

COMMENT ON VIEW warehouse.q06_monthly_volume IS
    'Monthly claim volume by service month with a 3-month moving average.';
