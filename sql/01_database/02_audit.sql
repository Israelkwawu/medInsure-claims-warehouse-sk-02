-- Operational tables for incremental loads and rows the warehouse refuses.
CREATE TABLE IF NOT EXISTS audit.etl_watermark (
    pipeline_name VARCHAR(50) PRIMARY KEY,
    high_water_mark DATE,
    rows_loaded BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE audit.etl_watermark IS
    'Highest processed_date already considered by a fact pipeline. The next run re-reads the boundary date so late arrivals on that date are not skipped.';

CREATE TABLE IF NOT EXISTS audit.etl_dead_letter (
    dead_letter_id BIGSERIAL PRIMARY KEY,
    pipeline_name VARCHAR(50) NOT NULL,
    source_table VARCHAR(63) NOT NULL,
    source_key TEXT NOT NULL,
    reject_reason VARCHAR(200) NOT NULL,
    rejected_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_etl_dead_letter_pipeline_key
    ON audit.etl_dead_letter (pipeline_name, source_key);

COMMENT ON TABLE audit.etl_dead_letter IS
    'Claims that cannot be placed on a member or provider version. The fact load continues; these rows are retried on the next run.';

-- Records the generator scale so quality and performance write-ups can cite the population they measured.
CREATE TABLE IF NOT EXISTS audit.load_profile (
    profile_id SMALLINT PRIMARY KEY,
    scale_factor NUMERIC(8, 4) NOT NULL,
    member_count INTEGER,
    provider_count INTEGER,
    claim_count INTEGER,
    claim_line_count INTEGER,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT load_profile_singleton CHECK (profile_id = 1)
);
