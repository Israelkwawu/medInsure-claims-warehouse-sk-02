-- Transaction fact. Grain: one row per service line within a claim.
-- Loaded only after fact_claim. claim_key is resolved from the degenerate
-- claim_id on the header. member_key and provider_key are copied from that
-- header so a line query does not re-interpret SCD.
CREATE TABLE IF NOT EXISTS warehouse.fact_claim_line (
    claim_line_key BIGSERIAL PRIMARY KEY,
    claim_key BIGINT NOT NULL REFERENCES warehouse.fact_claim (claim_key),
    claim_id BIGINT NOT NULL,
    line_number SMALLINT NOT NULL,
    member_key BIGINT NOT NULL REFERENCES warehouse.dim_member (member_key),
    provider_key BIGINT NOT NULL REFERENCES warehouse.dim_provider (provider_key),
    procedure_key BIGINT NOT NULL REFERENCES warehouse.dim_procedure (procedure_key),
    diagnosis_key BIGINT NOT NULL REFERENCES warehouse.dim_diagnosis (diagnosis_key),
    service_date_key BIGINT NOT NULL REFERENCES warehouse.dim_date (date_key),
    source_procedure_code VARCHAR(10) NOT NULL,
    units NUMERIC(6, 2) NOT NULL,
    billed_amount NUMERIC(12, 2) NOT NULL,
    allowed_amount NUMERIC(12, 2) NOT NULL,
    paid_amount NUMERIC(12, 2) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_fact_claim_line_natural UNIQUE (claim_id, line_number),
    CONSTRAINT fact_claim_line_amounts_ck CHECK (
        billed_amount >= 0
        AND allowed_amount >= 0
        AND paid_amount >= 0
        AND units > 0
    )
);

CREATE INDEX IF NOT EXISTS idx_fact_claim_line_claim_key
    ON warehouse.fact_claim_line (claim_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_line_member_key
    ON warehouse.fact_claim_line (member_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_line_provider_key
    ON warehouse.fact_claim_line (provider_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_line_procedure_key
    ON warehouse.fact_claim_line (procedure_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_line_diagnosis_key
    ON warehouse.fact_claim_line (diagnosis_key);
CREATE INDEX IF NOT EXISTS idx_fact_claim_line_service_date_key
    ON warehouse.fact_claim_line (service_date_key);

COMMENT ON TABLE warehouse.fact_claim_line IS
    'Transaction fact at service-line grain. Depends on fact_claim. Unknown procedure or diagnosis codes use the -1 placeholder and are retained.';
COMMENT ON COLUMN warehouse.fact_claim_line.claim_id IS
    'Degenerate dimension, copied from the header so line-to-header reconciliation does not require a join.';
COMMENT ON COLUMN warehouse.fact_claim_line.line_number IS
    'Degenerate line number within the claim.';
COMMENT ON COLUMN warehouse.fact_claim_line.source_procedure_code IS
    'Code as received. Kept so orphaned CPT codes remain visible after procedure_key is set to Not Applicable.';
