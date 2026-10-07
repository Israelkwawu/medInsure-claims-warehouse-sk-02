-- ICD-10 codes are reference data. A description correction overwrites the row
-- (Type 1). category_code is the three-character family above the full code.
CREATE TABLE IF NOT EXISTS warehouse.dim_diagnosis (
    diagnosis_key BIGSERIAL PRIMARY KEY,
    diagnosis_code VARCHAR(10) NOT NULL UNIQUE,
    description VARCHAR(160) NOT NULL,
    category_code VARCHAR(7) NOT NULL,
    category_name VARCHAR(80) NOT NULL
);

COMMENT ON TABLE warehouse.dim_diagnosis IS
    'SCD Type 1 ICD-10 dimension. diagnosis_code N/A / diagnosis_key -1 is Not Applicable.';
COMMENT ON COLUMN warehouse.dim_diagnosis.category_name IS
    'Rollup used by the diagnosis-category spend ranking. Kept on the dimension so facts stay at code grain.';
