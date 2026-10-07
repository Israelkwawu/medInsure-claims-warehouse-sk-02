-- Business question: how many claims does a member generate in the first 12
-- months after enrollment, and does that frequency differ by enrollment year?
-- enrollment_date is stable on dim_member, and every claim already points at
-- the member version in effect on the service date. The OLTP system only keeps
-- 18 months of plan history, so a 2020 cohort cannot be rebuilt there.
CREATE OR REPLACE VIEW warehouse.q07_member_cohort AS
WITH cohort AS (
    SELECT
        member_id,
        MIN(enrollment_date) AS enrollment_date,
        EXTRACT(YEAR FROM MIN(enrollment_date))::integer AS cohort_year
    FROM warehouse.dim_member
    WHERE member_key <> -1
    GROUP BY member_id
),
claims_12 AS (
    SELECT
        dm.member_id,
        COUNT(*) AS claims_in_first_12_months
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_member AS dm
        ON dm.member_key = f.member_key
    JOIN warehouse.dim_date AS sd
        ON sd.date_key = f.service_date_key
    WHERE sd.calendar_date >= dm.enrollment_date
      AND sd.calendar_date < dm.enrollment_date + INTERVAL '12 months'
    GROUP BY dm.member_id
),
summary AS (
    SELECT
        cohort.cohort_year,
        COUNT(*) AS members,
        ROUND(AVG(COALESCE(claims_12.claims_in_first_12_months, 0)), 2) AS avg_claims_first_12_months
    FROM cohort
    LEFT JOIN claims_12
        ON claims_12.member_id = cohort.member_id
    GROUP BY cohort.cohort_year
)
SELECT
    summary.cohort_year,
    summary.members,
    summary.avg_claims_first_12_months,
    RANK() OVER (ORDER BY summary.avg_claims_first_12_months DESC) AS frequency_rank,
    ROUND(
        AVG(summary.avg_claims_first_12_months) OVER (
            ORDER BY summary.cohort_year
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS cumulative_avg_frequency
FROM summary
ORDER BY summary.cohort_year;

COMMENT ON VIEW warehouse.q07_member_cohort IS
    'Claim frequency in the first 12 months after enrollment, by enrollment year.';
