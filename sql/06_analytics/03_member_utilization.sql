-- Business question: how many claims per 1,000 members do we see each month,
-- by plan type?
-- The SCD member dimension supplies who was covered during the month and which
-- plan they were on. The OLTP member row only has the current plan, so a
-- historical utilization rate would be wrong there. COUNT OVER accumulates the
-- months observed for each plan type.
CREATE OR REPLACE VIEW warehouse.q03_member_utilization AS
WITH months AS (
    SELECT
        year_month,
        MIN(calendar_date) AS month_start,
        MAX(calendar_date) AS month_end
    FROM warehouse.dim_date
    WHERE calendar_date BETWEEN DATE '2020-01-01' AND DATE '2026-09-30'
    GROUP BY year_month
),
enrolled AS (
    SELECT
        months.year_month,
        pl.plan_type,
        dm.member_id
    FROM months
    JOIN warehouse.dim_member AS dm
        ON dm.member_key <> -1
       AND dm.effective_start <= months.month_end
       AND dm.effective_end >= months.month_start
    JOIN warehouse.dim_plan AS pl
        ON pl.plan_key = dm.plan_key
    GROUP BY months.year_month, pl.plan_type, dm.member_id
),
enrolled_counts AS (
    SELECT
        year_month,
        plan_type,
        COUNT(*) AS member_count
    FROM enrolled
    GROUP BY year_month, plan_type
),
claim_counts AS (
    SELECT
        d.year_month,
        pl.plan_type,
        COUNT(*) AS claim_count
    FROM warehouse.fact_claim AS f
    JOIN warehouse.dim_date AS d
        ON d.date_key = f.service_date_key
    JOIN warehouse.dim_plan AS pl
        ON pl.plan_key = f.plan_key
    GROUP BY d.year_month, pl.plan_type
)
SELECT
    enrolled_counts.plan_type,
    enrolled_counts.year_month,
    enrolled_counts.member_count,
    COALESCE(claim_counts.claim_count, 0) AS claim_count,
    ROUND(
        1000.0 * COALESCE(claim_counts.claim_count, 0)
        / NULLIF(enrolled_counts.member_count, 0),
        2
    ) AS claims_per_1000_members,
    COUNT(*) OVER (
        PARTITION BY enrolled_counts.plan_type
        ORDER BY enrolled_counts.year_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_months
FROM enrolled_counts
LEFT JOIN claim_counts
    ON claim_counts.year_month = enrolled_counts.year_month
   AND claim_counts.plan_type = enrolled_counts.plan_type
ORDER BY enrolled_counts.plan_type, enrolled_counts.year_month;

COMMENT ON VIEW warehouse.q03_member_utilization IS
    'Monthly claims per 1,000 members by plan type, using SCD coverage as the denominator.';
