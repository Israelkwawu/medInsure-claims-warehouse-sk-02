-- Incremental header load. The high-water mark is processed_date.
-- The boundary date is re-read so a claim that arrives late on that date is
-- still considered; claim_id uniqueness keeps the reload idempotent.
-- A claim with no member or provider version is written to the dead-letter
-- log and skipped. The rest of the batch still loads.
CREATE OR REPLACE PROCEDURE warehouse.load_fact_claim()
LANGUAGE plpgsql
AS $$
DECLARE
    v_hwm date;
    v_max_date date;
    v_inserted bigint;
BEGIN
    SELECT high_water_mark
    INTO v_hwm
    FROM audit.etl_watermark
    WHERE pipeline_name = 'fact_claim';

    TRUNCATE TABLE staging.claim_load_batch;

    INSERT INTO staging.claim_load_batch (
        claim_id, member_key, provider_key, plan_key, service_date_key, processed_date_key,
        diagnosis_key, claim_type, claim_status, denial_reason,
        total_billed, total_allowed, total_paid, line_count, processed_date, reject_reason
    )
    SELECT
        c.claim_id,
        dm.member_key,
        dp.provider_key,
        dm.plan_key,
        sd.date_key,
        pd.date_key,
        COALESCE(dx.diagnosis_key, -1),
        c.claim_type,
        c.claim_status,
        c.denial_reason,
        c.total_billed,
        c.total_allowed,
        c.total_paid,
        COALESCE(lc.line_count, 0),
        c.processed_date,
        CASE
            WHEN dm.member_key IS NULL THEN 'member not found for service date'
            WHEN dp.provider_key IS NULL THEN 'provider not found for service date'
            WHEN sd.date_key IS NULL THEN 'service date not in dim_date'
            WHEN pd.date_key IS NULL THEN 'processed date not in dim_date'
            ELSE NULL
        END
    FROM source.claims AS c
    LEFT JOIN warehouse.dim_member AS dm
        ON dm.member_id = c.member_id
       AND dm.member_key <> -1
       AND c.service_date BETWEEN dm.effective_start AND dm.effective_end
    LEFT JOIN warehouse.dim_provider AS dp
        ON dp.provider_id = c.provider_id
       AND dp.provider_key <> -1
       AND c.service_date BETWEEN dp.effective_start AND dp.effective_end
    LEFT JOIN warehouse.dim_date AS sd
        ON sd.calendar_date = c.service_date
    LEFT JOIN warehouse.dim_date AS pd
        ON pd.calendar_date = c.processed_date
    LEFT JOIN warehouse.dim_diagnosis AS dx
        ON dx.diagnosis_code = c.primary_diagnosis_code
       AND dx.diagnosis_key <> -1
    LEFT JOIN (
        SELECT claim_id, COUNT(*)::integer AS line_count
        FROM source.claim_lines
        GROUP BY claim_id
    ) AS lc ON lc.claim_id = c.claim_id
    WHERE NOT EXISTS (
            SELECT 1
            FROM warehouse.fact_claim AS existing
            WHERE existing.claim_id = c.claim_id
        )
      AND (
            c.processed_date >= COALESCE(v_hwm, DATE '1900-01-01')
            OR EXISTS (
                SELECT 1
                FROM audit.etl_dead_letter AS prior
                WHERE prior.pipeline_name = 'fact_claim'
                  AND prior.source_key = c.claim_id::text
            )
        );

    DELETE FROM audit.etl_dead_letter AS prior
    USING staging.claim_load_batch AS batch
    WHERE prior.pipeline_name = 'fact_claim'
      AND prior.source_key = batch.claim_id::text;

    INSERT INTO audit.etl_dead_letter (pipeline_name, source_table, source_key, reject_reason)
    SELECT
        'fact_claim',
        'source.claims',
        claim_id::text,
        reject_reason
    FROM staging.claim_load_batch
    WHERE reject_reason IS NOT NULL;

    INSERT INTO warehouse.fact_claim (
        claim_id, member_key, provider_key, plan_key, primary_diagnosis_key,
        service_date_key, processed_date_key, claim_type, claim_status, denial_reason,
        total_billed, total_allowed, total_paid, member_responsibility, line_count
    )
    SELECT
        claim_id,
        member_key,
        provider_key,
        plan_key,
        diagnosis_key,
        service_date_key,
        processed_date_key,
        claim_type,
        claim_status,
        denial_reason,
        total_billed,
        total_allowed,
        total_paid,
        CASE
            WHEN claim_status = 'Denied' THEN 0
            ELSE GREATEST(total_allowed - total_paid, 0)
        END,
        line_count
    FROM staging.claim_load_batch
    WHERE reject_reason IS NULL;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    SELECT MAX(processed_date)
    INTO v_max_date
    FROM staging.claim_load_batch;

    IF v_max_date IS NOT NULL THEN
        INSERT INTO audit.etl_watermark (pipeline_name, high_water_mark, rows_loaded, updated_at)
        VALUES ('fact_claim', v_max_date, v_inserted, now())
        ON CONFLICT (pipeline_name) DO UPDATE
        SET
            high_water_mark = GREATEST(audit.etl_watermark.high_water_mark, EXCLUDED.high_water_mark),
            rows_loaded = audit.etl_watermark.rows_loaded + EXCLUDED.rows_loaded,
            updated_at = now();
    END IF;

    RAISE NOTICE 'fact_claim inserted %, rejected %',
        v_inserted,
        (SELECT COUNT(*) FROM staging.claim_load_batch WHERE reject_reason IS NOT NULL);
END;
$$;
