-- Type 1 upsert on the ICD-10 code. Description and category corrections overwrite.
CREATE OR REPLACE PROCEDURE warehouse.load_dim_diagnosis()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL warehouse.seed_unknown_rows();

    INSERT INTO warehouse.dim_diagnosis (
        diagnosis_code, description, category_code, category_name
    )
    SELECT diagnosis_code, description, category_code, category_name
    FROM source.diagnosis_codes
    ON CONFLICT (diagnosis_code) DO UPDATE
    SET
        description = EXCLUDED.description,
        category_code = EXCLUDED.category_code,
        category_name = EXCLUDED.category_name;
END;
$$;
