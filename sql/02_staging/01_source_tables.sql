-- OLTP-shaped source. member_id and provider_id on claims are intentionally not
-- foreign keys: the source is allowed to contain orphans so the warehouse can
-- dead-letter them instead of aborting the load.

CREATE TABLE IF NOT EXISTS source.plan_types (
    plan_id SMALLINT PRIMARY KEY,
    plan_code VARCHAR(10) NOT NULL UNIQUE,
    plan_name VARCHAR(40) NOT NULL,
    plan_type VARCHAR(10) NOT NULL,
    deductible NUMERIC(10, 2) NOT NULL,
    oop_max NUMERIC(10, 2) NOT NULL,
    coinsurance_pct NUMERIC(5, 2) NOT NULL,
    CONSTRAINT plan_types_type_ck CHECK (plan_type IN ('HMO', 'PPO', 'EPO', 'HDHP'))
);

CREATE TABLE IF NOT EXISTS source.diagnosis_codes (
    diagnosis_code VARCHAR(10) PRIMARY KEY,
    description VARCHAR(160) NOT NULL,
    category_code VARCHAR(7) NOT NULL,
    category_name VARCHAR(80) NOT NULL
);

CREATE TABLE IF NOT EXISTS source.procedure_codes (
    procedure_code VARCHAR(10) PRIMARY KEY,
    description VARCHAR(160) NOT NULL,
    category_name VARCHAR(80) NOT NULL
);

CREATE TABLE IF NOT EXISTS source.members (
    member_id BIGINT PRIMARY KEY,
    first_name VARCHAR(40) NOT NULL,
    last_name VARCHAR(40) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender CHAR(1) NOT NULL,
    plan_id SMALLINT NOT NULL REFERENCES source.plan_types (plan_id),
    state CHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    enrollment_date DATE NOT NULL,
    CONSTRAINT members_gender_ck CHECK (gender IN ('F', 'M', 'X'))
);

CREATE TABLE IF NOT EXISTS source.member_plan_history (
    history_id BIGSERIAL PRIMARY KEY,
    member_id BIGINT NOT NULL REFERENCES source.members (member_id),
    plan_id SMALLINT NOT NULL REFERENCES source.plan_types (plan_id),
    state CHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE,
    CONSTRAINT member_plan_history_dates_ck CHECK (
        effective_end IS NULL OR effective_end >= effective_start
    )
);

CREATE INDEX IF NOT EXISTS idx_member_plan_history_member
    ON source.member_plan_history (member_id, effective_start);

CREATE TABLE IF NOT EXISTS source.providers (
    provider_id BIGINT PRIMARY KEY,
    npi CHAR(10) NOT NULL UNIQUE,
    provider_name VARCHAR(80) NOT NULL,
    provider_type VARCHAR(20) NOT NULL,
    specialty VARCHAR(40) NOT NULL,
    network_status VARCHAR(20) NOT NULL,
    city VARCHAR(40) NOT NULL,
    state CHAR(2) NOT NULL,
    network_effective_date DATE NOT NULL,
    CONSTRAINT providers_type_ck CHECK (provider_type IN ('Physician', 'Hospital', 'Facility')),
    CONSTRAINT providers_network_ck CHECK (network_status IN ('In-Network', 'Out-of-Network'))
);

CREATE TABLE IF NOT EXISTS source.provider_network_history (
    history_id BIGSERIAL PRIMARY KEY,
    provider_id BIGINT NOT NULL REFERENCES source.providers (provider_id),
    network_status VARCHAR(20) NOT NULL,
    specialty VARCHAR(40) NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE,
    network_effective_date DATE NOT NULL,
    CONSTRAINT provider_network_history_dates_ck CHECK (
        effective_end IS NULL OR effective_end >= effective_start
    ),
    CONSTRAINT provider_network_history_network_ck CHECK (
        network_status IN ('In-Network', 'Out-of-Network')
    )
);

CREATE INDEX IF NOT EXISTS idx_provider_network_history_provider
    ON source.provider_network_history (provider_id, effective_start);

CREATE TABLE IF NOT EXISTS source.claims (
    claim_id BIGINT PRIMARY KEY,
    member_id BIGINT NOT NULL,
    provider_id BIGINT NOT NULL,
    primary_diagnosis_code VARCHAR(10) NOT NULL,
    claim_type VARCHAR(20) NOT NULL,
    claim_status VARCHAR(20) NOT NULL,
    denial_reason VARCHAR(40),
    service_date DATE NOT NULL,
    processed_date DATE NOT NULL,
    total_billed NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_allowed NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_paid NUMERIC(12, 2) NOT NULL DEFAULT 0,
    CONSTRAINT claims_type_ck CHECK (
        claim_type IN ('Professional', 'Inpatient', 'Outpatient', 'Emergency')
    ),
    CONSTRAINT claims_status_ck CHECK (claim_status IN ('Paid', 'Denied')),
    CONSTRAINT claims_processed_ck CHECK (processed_date >= service_date)
);

CREATE INDEX IF NOT EXISTS idx_claims_processed_date
    ON source.claims (processed_date);

CREATE TABLE IF NOT EXISTS source.claim_lines (
    claim_line_id BIGINT PRIMARY KEY,
    claim_id BIGINT NOT NULL REFERENCES source.claims (claim_id),
    line_number SMALLINT NOT NULL,
    procedure_code VARCHAR(10) NOT NULL,
    diagnosis_code VARCHAR(10) NOT NULL,
    service_date DATE NOT NULL,
    units NUMERIC(6, 2) NOT NULL,
    billed_amount NUMERIC(12, 2) NOT NULL,
    allowed_amount NUMERIC(12, 2) NOT NULL,
    paid_amount NUMERIC(12, 2) NOT NULL,
    CONSTRAINT claim_lines_natural_key UNIQUE (claim_id, line_number),
    CONSTRAINT claim_lines_amounts_ck CHECK (
        billed_amount >= 0 AND allowed_amount >= 0 AND paid_amount >= 0 AND units > 0
    )
);

CREATE INDEX IF NOT EXISTS idx_claim_lines_claim_id
    ON source.claim_lines (claim_id);
