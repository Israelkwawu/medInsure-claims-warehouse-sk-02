-- Type 2 provider history. network_status and specialty are tracked. The
-- network_effective_date stays with the network status when only the specialty
-- changes, which is what the anachronism quality check compares to service date.
CREATE TABLE IF NOT EXISTS warehouse.dim_provider (
    provider_key BIGSERIAL PRIMARY KEY,
    provider_id BIGINT NOT NULL,
    npi CHAR(10) NOT NULL,
    provider_name VARCHAR(80) NOT NULL,
    provider_type VARCHAR(20) NOT NULL,
    specialty VARCHAR(40) NOT NULL,
    network_status VARCHAR(20) NOT NULL,
    city VARCHAR(40) NOT NULL,
    state CHAR(2) NOT NULL,
    network_effective_date DATE NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE NOT NULL,
    is_current BOOLEAN NOT NULL,
    CONSTRAINT dim_provider_dates_ck CHECK (effective_end >= effective_start),
    CONSTRAINT uq_dim_provider_version UNIQUE (provider_id, effective_start)
);

CREATE INDEX IF NOT EXISTS idx_dim_provider_scd_lookup
    ON warehouse.dim_provider (provider_id, effective_start, effective_end);

CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_provider_one_current
    ON warehouse.dim_provider (provider_id)
    WHERE is_current;

COMMENT ON TABLE warehouse.dim_provider IS
    'SCD Type 2 provider dimension. provider_id -1 / provider_key -1 is Not Applicable. Also conformed for a future pharmacy prescriber role.';
COMMENT ON COLUMN warehouse.dim_provider.network_effective_date IS
    'Date the network_status on this version took effect. Specialty-only changes carry the previous network date forward.';
