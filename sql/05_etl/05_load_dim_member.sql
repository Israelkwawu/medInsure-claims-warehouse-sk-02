-- SCD Type 2 for dim_member.
-- Version 1 is the initial snapshot (inserted as the current open row).
-- Each later version uses the two-step close-then-insert pattern:
--   1. Close the current row when plan_id, state, or zip_code IS DISTINCT FROM the new values.
--   2. Insert the new current row when that member no longer has an open version.
-- IS DISTINCT FROM treats NULL as a real change. Re-running is a no-op once the
-- current row already matches the latest history version.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_member()
LANGUAGE plpgsql
AS $$
DECLARE
    v_max integer;
    v_rn integer;
BEGIN
    CALL warehouse.seed_unknown_rows();

    SELECT COALESCE(MAX(version_rank), 1)
    INTO v_max
    FROM staging.member_history;

    INSERT INTO warehouse.dim_member (
        member_id, first_name, last_name, date_of_birth, gender,
        plan_key, plan_id, state, zip_code, enrollment_date,
        effective_start, effective_end, is_current
    )
    SELECT
        h.member_id,
        h.first_name,
        h.last_name,
        h.date_of_birth,
        h.gender,
        pl.plan_key,
        h.plan_id,
        h.state,
        h.zip_code,
        h.enrollment_date,
        h.effective_start,
        DATE '9999-12-31',
        TRUE
    FROM staging.member_history AS h
    JOIN warehouse.dim_plan AS pl ON pl.plan_id = h.plan_id
    WHERE h.version_rank = 1
      AND NOT EXISTS (
          SELECT 1
          FROM warehouse.dim_member AS existing
          WHERE existing.member_id = h.member_id
      );

    FOR v_rn IN 2..v_max LOOP
        -- Step 1: close the open version.
        UPDATE warehouse.dim_member AS d
        SET
            effective_end = h.effective_start - 1,
            is_current = FALSE
        FROM staging.member_history AS h
        WHERE h.version_rank = v_rn
          AND d.member_id = h.member_id
          AND d.is_current
          AND d.effective_start < h.effective_start
          AND (
              d.plan_id IS DISTINCT FROM h.plan_id
              OR d.state IS DISTINCT FROM h.state
              OR d.zip_code IS DISTINCT FROM h.zip_code
          );

        -- Step 2: insert the new current version.
        INSERT INTO warehouse.dim_member (
            member_id, first_name, last_name, date_of_birth, gender,
            plan_key, plan_id, state, zip_code, enrollment_date,
            effective_start, effective_end, is_current
        )
        SELECT
            h.member_id,
            h.first_name,
            h.last_name,
            h.date_of_birth,
            h.gender,
            pl.plan_key,
            h.plan_id,
            h.state,
            h.zip_code,
            h.enrollment_date,
            h.effective_start,
            DATE '9999-12-31',
            TRUE
        FROM staging.member_history AS h
        JOIN warehouse.dim_plan AS pl ON pl.plan_id = h.plan_id
        WHERE h.version_rank = v_rn
          AND NOT EXISTS (
              SELECT 1
              FROM warehouse.dim_member AS existing
              WHERE existing.member_id = h.member_id
                AND existing.is_current
          );

        RAISE NOTICE 'dim_member applied history version %', v_rn;
    END LOOP;

    -- Verification: no member has more than one is_current = TRUE row.
    IF EXISTS (
        SELECT member_id
        FROM warehouse.dim_member
        WHERE is_current
        GROUP BY member_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'dim_member has more than one is_current row for a member';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM warehouse.dim_member AS a
        JOIN warehouse.dim_member AS b
            ON a.member_id = b.member_id
           AND a.member_key < b.member_key
           AND a.effective_start <= b.effective_end
           AND b.effective_start <= a.effective_end
    ) THEN
        RAISE EXCEPTION 'dim_member has overlapping SCD versions';
    END IF;
END;
$$;
