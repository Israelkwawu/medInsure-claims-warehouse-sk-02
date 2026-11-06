-- Operational tables for incremental loads and rows the warehouse refuses.
CREATE TABLE IF NOT EXISTS audit.etl_watermark (
    pipeline_name VARCHAR(50) PRIMARY KEY,
    high_water_mark DATE,
    rows_loaded BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE audit.etl_watermark IS
    'Latest processed_date considered by a fact pipeline. The mark records progress. It does not exclude a claim that has never been loaded or rejected.';

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
    'Source rows the fact load could not place. The load writes the row here and continues. fact_claim: no member, provider, or calendar row. fact_claim_line: the header was rejected, the header is missing, or the service date is not on the calendar. Unknown diagnosis and procedure codes are not rejected; the line loads with key -1. Retried on the next run.';

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
