-- Type 1 upsert. plan_id is the natural key. The Not Applicable row (plan_id 0)
-- is not in the source and is never updated by this load.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_plan()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL warehouse.seed_unknown_rows();

    INSERT INTO warehouse.dim_plan (
        plan_id, plan_code, plan_name, plan_type, deductible, oop_max, coinsurance_pct
    )
    SELECT
        plan_id, plan_code, plan_name, plan_type, deductible, oop_max, coinsurance_pct
    FROM source.plan_types
    ON CONFLICT (plan_id) DO UPDATE
    SET
        plan_code = EXCLUDED.plan_code,
        plan_name = EXCLUDED.plan_name,
        plan_type = EXCLUDED.plan_type,
        deductible = EXCLUDED.deductible,
        oop_max = EXCLUDED.oop_max,
        coinsurance_pct = EXCLUDED.coinsurance_pct;
END;
$$;
