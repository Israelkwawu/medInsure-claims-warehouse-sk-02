-- Not Applicable placeholders. Nullable fact foreign keys point here instead of
-- storing NULL, so analytic joins do not drop the row.
CREATE OR REPLACE PROCEDURE warehouse.seed_unknown_rows()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO warehouse.dim_plan (
        plan_key, plan_id, plan_code, plan_name, plan_type, deductible, oop_max, coinsurance_pct
    )
    SELECT -1, 0, 'N/A', 'Not Applicable', 'N/A', 0, 0, 0
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_plan WHERE plan_key = -1);

    INSERT INTO warehouse.dim_date (
        date_key, calendar_date, year_number, quarter_number, month_number, month_name,
        day_of_month, day_of_week, day_name, week_of_year, is_weekend, year_month
    )
    SELECT -1, NULL, 0, 0, 0, 'Not Applicable', 0, 0, 'Not Applicable', 0, FALSE, 'N/A'
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_date WHERE date_key = -1);

    INSERT INTO warehouse.dim_diagnosis (
        diagnosis_key, diagnosis_code, description, category_code, category_name
    )
    SELECT -1, 'N/A', 'Not Applicable', 'N/A', 'Not Applicable'
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_diagnosis WHERE diagnosis_key = -1);

    INSERT INTO warehouse.dim_procedure (
        procedure_key, procedure_code, description, category_name
    )
    SELECT -1, 'N/A', 'Not Applicable', 'Not Applicable'
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_procedure WHERE procedure_key = -1);

    INSERT INTO warehouse.dim_member (
        member_key, member_id, first_name, last_name, date_of_birth, gender,
        plan_key, plan_id, state, zip_code, enrollment_date,
        effective_start, effective_end, is_current
    )
    SELECT
        -1, -1, 'Not Applicable', 'Not Applicable', NULL, 'U',
        -1, 0, 'NA', '00000', DATE '1900-01-01',
        DATE '1900-01-01', DATE '9999-12-31', TRUE
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_member WHERE member_key = -1);

    INSERT INTO warehouse.dim_provider (
        provider_key, provider_id, npi, provider_name, provider_type, specialty,
        network_status, city, state, network_effective_date,
        effective_start, effective_end, is_current
    )
    SELECT
        -1, -1, '0000000000', 'Not Applicable', 'Not Applicable', 'Not Applicable',
        'Not Applicable', 'Not Applicable', 'NA', DATE '1900-01-01',
        DATE '1900-01-01', DATE '9999-12-31', TRUE
    WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_provider WHERE provider_key = -1);
END;
$$;

CREATE OR REPLACE PROCEDURE warehouse.reset_warehouse_data()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE
        warehouse.fact_claim_line,
        warehouse.fact_claim,
        warehouse.dim_member,
        warehouse.dim_provider,
        warehouse.dim_diagnosis,
        warehouse.dim_procedure,
        warehouse.dim_plan,
        warehouse.dim_date,
        staging.claim_load_batch,
        audit.etl_dead_letter,
        audit.etl_watermark
    RESTART IDENTITY;

    CALL warehouse.seed_unknown_rows();
END;
$$;

CALL warehouse.seed_unknown_rows();
