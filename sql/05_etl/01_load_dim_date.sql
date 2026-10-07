-- Calendar population is pure SQL, 2020 through 2030 inclusive. The Not Applicable
-- row is left in place; its calendar_date is null so it does not collide.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_date()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL warehouse.seed_unknown_rows();

    INSERT INTO warehouse.dim_date (
        calendar_date, year_number, quarter_number, month_number, month_name,
        day_of_month, day_of_week, day_name, week_of_year, is_weekend, year_month
    )
    SELECT
        g::date,
        EXTRACT(YEAR FROM g)::smallint,
        EXTRACT(QUARTER FROM g)::smallint,
        EXTRACT(MONTH FROM g)::smallint,
        TRIM(TO_CHAR(g, 'Month')),
        EXTRACT(DAY FROM g)::smallint,
        EXTRACT(ISODOW FROM g)::smallint,
        TRIM(TO_CHAR(g, 'Day')),
        EXTRACT(WEEK FROM g)::smallint,
        EXTRACT(ISODOW FROM g) >= 6,
        TO_CHAR(g, 'YYYY-MM')
    FROM generate_series(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1 day') AS g
    WHERE NOT EXISTS (
        SELECT 1
        FROM warehouse.dim_date AS existing
        WHERE existing.calendar_date = g::date
    );
END;
$$;
