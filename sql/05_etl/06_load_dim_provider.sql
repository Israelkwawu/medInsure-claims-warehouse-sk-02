-- SCD Type 2 for dim_provider. Tracked attributes: network_status, specialty.
-- network_effective_date is copied from history. Specialty-only changes carry
-- the previous network date forward; that value is already on the history row.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_provider()
LANGUAGE plpgsql
AS $$
DECLARE
    v_max integer;
    v_rn integer;
BEGIN
    CALL warehouse.seed_unknown_rows();

    SELECT COALESCE(MAX(version_rank), 1)
    INTO v_max
    FROM staging.provider_history;

    INSERT INTO warehouse.dim_provider (
        provider_id, npi, provider_name, provider_type, specialty, network_status,
        city, state, network_effective_date, effective_start, effective_end, is_current
    )
    SELECT
        h.provider_id,
        h.npi,
        h.provider_name,
        h.provider_type,
        h.specialty,
        h.network_status,
        h.city,
        h.state,
        h.network_effective_date,
        h.effective_start,
        DATE '9999-12-31',
        TRUE
    FROM staging.provider_history AS h
    WHERE h.version_rank = 1
      AND NOT EXISTS (
          SELECT 1
          FROM warehouse.dim_provider AS existing
          WHERE existing.provider_id = h.provider_id
      );

    FOR v_rn IN 2..v_max LOOP
        -- Step 1: close the open version.
        UPDATE warehouse.dim_provider AS d
        SET
            effective_end = h.effective_start - 1,
            is_current = FALSE
        FROM staging.provider_history AS h
        WHERE h.version_rank = v_rn
          AND d.provider_id = h.provider_id
          AND d.is_current
          AND d.effective_start < h.effective_start
          AND (
              d.network_status IS DISTINCT FROM h.network_status
              OR d.specialty IS DISTINCT FROM h.specialty
          );

        -- Step 2: insert the new current version.
        INSERT INTO warehouse.dim_provider (
            provider_id, npi, provider_name, provider_type, specialty, network_status,
            city, state, network_effective_date, effective_start, effective_end, is_current
        )
        SELECT
            h.provider_id,
            h.npi,
            h.provider_name,
            h.provider_type,
            h.specialty,
            h.network_status,
            h.city,
            h.state,
            h.network_effective_date,
            h.effective_start,
            DATE '9999-12-31',
            TRUE
        FROM staging.provider_history AS h
        WHERE h.version_rank = v_rn
          AND NOT EXISTS (
              SELECT 1
              FROM warehouse.dim_provider AS existing
              WHERE existing.provider_id = h.provider_id
                AND existing.is_current
          );

        RAISE NOTICE 'dim_provider applied history version %', v_rn;
    END LOOP;

    -- Verification: no provider has more than one is_current = TRUE row.
    IF EXISTS (
        SELECT provider_id
        FROM warehouse.dim_provider
        WHERE is_current
        GROUP BY provider_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'dim_provider has more than one is_current row for a provider';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM warehouse.dim_provider AS a
        JOIN warehouse.dim_provider AS b
            ON a.provider_id = b.provider_id
           AND a.provider_key < b.provider_key
           AND a.effective_start <= b.effective_end
           AND b.effective_start <= a.effective_end
    ) THEN
        RAISE EXCEPTION 'dim_provider has overlapping SCD versions';
    END IF;
END;
$$;
