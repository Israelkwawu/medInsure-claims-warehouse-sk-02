-- Transaction fact. Grain: one row per claim header (one adjudicated encounter).
-- claim_id is a degenerate dimension. service_date_key and processed_date_key
-- are two roles of dim_date. Measures are additive across claims.
CREATE TABLE IF NOT EXISTS warehouse.fact_claim (
    claim_key BIGSERIAL PRIMARY KEY,
    claim_id BIGINT NOT NULL,
    member_key BIGINT NOT NULL REFERENCES warehouse.dim_member (member_key),
    provider_key BIGINT NOT NULL REFERENCES warehouse.dim_provider (provider_key),
    plan_key BIGINT NOT NULL REFERENCES warehouse.dim_plan (plan_key),
    primary_diagnosis_key BIGINT NOT NULL REFERENCES warehouse.dim_diagnosis (diagnosis_key),
    service_date_key BIGINT NOT NULL REFERENCES warehouse.dim_date (date_key),
    processed_date_key BIGINT NOT NULL REFERENCES warehouse.dim_date (date_key),
    claim_type VARCHAR(20) NOT NULL,
    claim_status VARCHAR(20) NOT NULL,
    denial_reason VARCHAR(40),
    total_billed NUMERIC(12, 2) NOT NULL,
    total_allowed NUMERIC(12, 2) NOT NULL,
    total_paid NUMERIC(12, 2) NOT NULL,
    member_responsibility NUMERIC(12, 2) NOT NULL,
    line_count INTEGER NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_fact_claim_claim_id UNIQUE (claim_id),
    CONSTRAINT fact_claim_amounts_ck CHECK (
        total_billed >= 0
        AND total_allowed >= 0
        AND total_paid >= 0
        AND member_responsibility >= 0
        AND line_count >= 0
    )
);

-- Every foreign key has its own B-tree. The unique claim_id index is the
-- lookup path from fact_claim_line back to the header.
CREATE INDEX IF NOT EXISTS idx_fact_claim_member_key
    ON warehouse.fact_claim (member_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_provider_key
    ON warehouse.fact_claim (provider_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_plan_key
    ON warehouse.fact_claim (plan_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_diagnosis_key
    ON warehouse.fact_claim (primary_diagnosis_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_service_date_key
    ON warehouse.fact_claim (service_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_processed_date_key
    ON warehouse.fact_claim (processed_date_key);

COMMENT ON TABLE warehouse.fact_claim IS
    'Transaction fact at header grain: one row per claim. claim_id is degenerate and is not a dimension table.';
COMMENT ON COLUMN warehouse.fact_claim.claim_id IS
    'Degenerate dimension. Natural claim number kept on the fact for drill-through and for the line load lookup.';
COMMENT ON COLUMN warehouse.fact_claim.plan_key IS
    'Plan on the member version that was effective on the service date, not the member''s current plan.';
COMMENT ON COLUMN warehouse.fact_claim.member_responsibility IS
    'Allowed minus paid for paid claims. Zero when the claim is denied. Not constrained against total_allowed so the 5% quality check can see source defects.';
