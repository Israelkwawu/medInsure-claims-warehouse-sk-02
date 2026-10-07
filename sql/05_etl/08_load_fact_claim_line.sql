-- Line load runs after fact_claim. claim_key is looked up from the degenerate
-- claim_id on the header. Lines whose header was dead-lettered are left behind
-- with that header. Unknown procedure or diagnosis codes use the -1 placeholder.
CREATE OR REPLACE PROCEDURE warehouse.load_fact_claim_line()
LANGUAGE plpgsql
AS $$
DECLARE
    v_inserted bigint;
    v_hwm date;
BEGIN
    INSERT INTO warehouse.fact_claim_line (
        claim_key, claim_id, line_number, member_key, provider_key,
        procedure_key, diagnosis_key, service_date_key, source_procedure_code,
        units, billed_amount, allowed_amount, paid_amount
    )
    SELECT
        header.claim_key,
        line.claim_id,
        line.line_number,
        header.member_key,
        header.provider_key,
        COALESCE(proc.procedure_key, -1),
        COALESCE(dx.diagnosis_key, -1),
        service_date.date_key,
        line.procedure_code,
        line.units,
        line.billed_amount,
        line.allowed_amount,
        line.paid_amount
    FROM source.claim_lines AS line
    JOIN warehouse.fact_claim AS header
        ON header.claim_id = line.claim_id
    JOIN warehouse.dim_date AS service_date
        ON service_date.calendar_date = line.service_date
    LEFT JOIN warehouse.dim_procedure AS proc
        ON proc.procedure_code = line.procedure_code
       AND proc.procedure_key <> -1
    LEFT JOIN warehouse.dim_diagnosis AS dx
        ON dx.diagnosis_code = line.diagnosis_code
       AND dx.diagnosis_key <> -1
    WHERE NOT EXISTS (
        SELECT 1
        FROM warehouse.fact_claim_line AS existing
        WHERE existing.claim_id = line.claim_id
          AND existing.line_number = line.line_number
    );

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    SELECT high_water_mark
    INTO v_hwm
    FROM audit.etl_watermark
    WHERE pipeline_name = 'fact_claim';

    INSERT INTO audit.etl_watermark (pipeline_name, high_water_mark, rows_loaded, updated_at)
    VALUES ('fact_claim_line', v_hwm, v_inserted, now())
    ON CONFLICT (pipeline_name) DO UPDATE
    SET
        high_water_mark = EXCLUDED.high_water_mark,
        rows_loaded = audit.etl_watermark.rows_loaded + EXCLUDED.rows_loaded,
        updated_at = now();

    RAISE NOTICE 'fact_claim_line inserted %', v_inserted;
END;
$$;
