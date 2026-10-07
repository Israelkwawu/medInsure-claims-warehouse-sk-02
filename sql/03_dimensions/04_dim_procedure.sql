-- CPT reference data. Category changes are corrections, so Type 1 upsert is enough.
CREATE TABLE IF NOT EXISTS warehouse.dim_procedure (
    procedure_key BIGSERIAL PRIMARY KEY,
    procedure_code VARCHAR(10) NOT NULL UNIQUE,
    description VARCHAR(160) NOT NULL,
    category_name VARCHAR(80) NOT NULL
);

COMMENT ON TABLE warehouse.dim_procedure IS
    'SCD Type 1 CPT dimension. procedure_code N/A / procedure_key -1 is Not Applicable.';
