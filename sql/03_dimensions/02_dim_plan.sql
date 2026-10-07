-- Plan attributes change by issuing a new plan_id, not by editing history,
-- so Type 1 is enough. Shared with a future fact_pharmacy table: a script and
-- a claim for the same member must resolve to the same plan row.
CREATE TABLE IF NOT EXISTS warehouse.dim_plan (
    plan_key BIGSERIAL PRIMARY KEY,
    plan_id SMALLINT NOT NULL UNIQUE,
    plan_code VARCHAR(10) NOT NULL,
    plan_name VARCHAR(40) NOT NULL,
    plan_type VARCHAR(10) NOT NULL,
    deductible NUMERIC(10, 2) NOT NULL,
    oop_max NUMERIC(10, 2) NOT NULL,
    coinsurance_pct NUMERIC(5, 2) NOT NULL,
    CONSTRAINT dim_plan_type_ck CHECK (plan_type IN ('HMO', 'PPO', 'EPO', 'HDHP', 'N/A'))
);

COMMENT ON TABLE warehouse.dim_plan IS
    'SCD Type 1 conformed plan dimension. plan_id 0 / plan_key -1 is Not Applicable.';
COMMENT ON COLUMN warehouse.dim_plan.plan_type IS
    'Product family used for utilization and benefit comparisons: HMO, PPO, EPO, HDHP.';
