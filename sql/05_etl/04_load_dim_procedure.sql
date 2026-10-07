-- Type 1 upsert on the CPT code.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_procedure()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL warehouse.seed_unknown_rows();

    INSERT INTO warehouse.dim_procedure (
        procedure_code, description, category_name
    )
    SELECT procedure_code, description, category_name
    FROM source.procedure_codes
    ON CONFLICT (procedure_code) DO UPDATE
    SET
        description = EXCLUDED.description,
        category_name = EXCLUDED.category_name;
END;
$$;
