-- Versioned history with a rank, ready for the SCD close-then-insert load.
-- Static member attributes come from the current member row; tracked attributes
-- come from history so a plan change does not rewrite the person's name.
CREATE OR REPLACE VIEW staging.member_history AS
SELECT
    h.history_id,
    h.member_id,
    h.plan_id,
    h.state,
    h.zip_code,
    h.effective_start,
    h.effective_end,
    m.first_name,
    m.last_name,
    m.date_of_birth,
    m.gender,
    m.enrollment_date,
    ROW_NUMBER() OVER (
        PARTITION BY h.member_id
        ORDER BY h.effective_start, h.history_id
    ) AS version_rank
FROM source.member_plan_history AS h
JOIN source.members AS m ON m.member_id = h.member_id;

CREATE OR REPLACE VIEW staging.provider_history AS
SELECT
    h.history_id,
    h.provider_id,
    h.network_status,
    h.specialty,
    h.effective_start,
    h.effective_end,
    h.network_effective_date,
    p.npi,
    p.provider_name,
    p.provider_type,
    p.city,
    p.state,
    ROW_NUMBER() OVER (
        PARTITION BY h.provider_id
        ORDER BY h.effective_start, h.history_id
    ) AS version_rank
FROM source.provider_network_history AS h
JOIN source.providers AS p ON p.provider_id = h.provider_id;

-- One resolved claim per load attempt. reject_reason is null when the row can enter fact_claim.
CREATE TABLE IF NOT EXISTS staging.claim_load_batch (
    claim_id BIGINT PRIMARY KEY,
    member_key BIGINT,
    provider_key BIGINT,
    plan_key BIGINT,
    service_date_key BIGINT,
    processed_date_key BIGINT,
    diagnosis_key BIGINT NOT NULL,
    claim_type VARCHAR(20) NOT NULL,
    claim_status VARCHAR(20) NOT NULL,
    denial_reason VARCHAR(40),
    total_billed NUMERIC(12, 2) NOT NULL,
    total_allowed NUMERIC(12, 2) NOT NULL,
    total_paid NUMERIC(12, 2) NOT NULL,
    line_count INTEGER NOT NULL,
    processed_date DATE NOT NULL,
    reject_reason VARCHAR(200)
);
