-- Line load runs after fact_claim. claim_key is looked up from the degenerate
-- claim_id on the header. A line that cannot be placed is written to the
-- dead-letter log and the load continues: header rejected, header missing, or
-- service date not on the calendar. Unknown procedure or diagnosis codes use
-- the -1 placeholder and the line still loads.
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

    -- Replace the line log for this run. A line that loaded is cleared.
    -- A line that did not load is written back with the current reason.
    -- The load does not raise.
    DELETE FROM audit.etl_dead_letter
    WHERE pipeline_name = 'fact_claim_line';

    INSERT INTO audit.etl_dead_letter (pipeline_name, source_table, source_key, reject_reason)
    SELECT
        'fact_claim_line',
        'source.claim_lines',
        line.claim_line_id::text,
        LEFT(
            CASE
                WHEN header.claim_key IS NULL AND header_reject.reject_reason IS NOT NULL
                    THEN 'header rejected: ' || header_reject.reject_reason
                WHEN header.claim_key IS NULL THEN 'header not loaded'
                WHEN service_date.date_key IS NULL THEN 'service date not in dim_date'
                ELSE 'line not loaded'
            END,
            200
        )
    FROM source.claim_lines AS line
    LEFT JOIN warehouse.fact_claim AS header
        ON header.claim_id = line.claim_id
    LEFT JOIN LATERAL (
        SELECT reject_reason
        FROM audit.etl_dead_letter AS prior
        WHERE prior.pipeline_name = 'fact_claim'
          AND prior.source_key = line.claim_id::text
        ORDER BY prior.dead_letter_id DESC
        LIMIT 1
    ) AS header_reject ON TRUE
    LEFT JOIN warehouse.dim_date AS service_date
        ON service_date.calendar_date = line.service_date
       AND service_date.date_key <> -1
    WHERE NOT EXISTS (
        SELECT 1
        FROM warehouse.fact_claim_line AS placed
        WHERE placed.claim_id = line.claim_id
          AND placed.line_number = line.line_number
    );

    -- Lines have no processed_date, so they record the header watermark they were loaded with.
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

    RAISE NOTICE 'fact_claim_line inserted %, rejected %',
        v_inserted,
        (SELECT COUNT(*) FROM audit.etl_dead_letter WHERE pipeline_name = 'fact_claim_line');
END;
$$;
