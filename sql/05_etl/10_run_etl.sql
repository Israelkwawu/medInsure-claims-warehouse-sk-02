-- Dependency order: conformed dimensions, then SCD dimensions, then the header
-- fact, then the line fact. Line load looks up claim_key on fact_claim.
CREATE OR REPLACE PROCEDURE warehouse.run_etl()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL warehouse.seed_unknown_rows();
    CALL warehouse.load_dim_date();
    CALL warehouse.load_dim_plan();
    CALL warehouse.load_dim_diagnosis();
    CALL warehouse.load_dim_procedure();
    CALL warehouse.load_dim_member();
    CALL warehouse.load_dim_provider();
    CALL warehouse.load_fact_claim();
    CALL warehouse.load_fact_claim_line();

    ANALYZE warehouse.dim_date;
    ANALYZE warehouse.dim_plan;
    ANALYZE warehouse.dim_diagnosis;
    ANALYZE warehouse.dim_procedure;
    ANALYZE warehouse.dim_member;
    ANALYZE warehouse.dim_provider;
    ANALYZE warehouse.fact_claim;
    ANALYZE warehouse.fact_claim_line;
END;
$$;
