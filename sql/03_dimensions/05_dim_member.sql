-- Type 2 membership history. plan_id, state, and zip_code are the tracked
-- attributes. Name, birth date, gender, and enrollment stay on every version
-- but do not open a new one. A future fact_pharmacy table uses member_key for
-- the same person-at-a-point-in-time.
CREATE TABLE IF NOT EXISTS warehouse.dim_member (
    member_key BIGSERIAL PRIMARY KEY,
    member_id BIGINT NOT NULL,
    first_name VARCHAR(40) NOT NULL,
    last_name VARCHAR(40) NOT NULL,
    date_of_birth DATE,
    gender CHAR(1) NOT NULL,
    plan_key BIGINT NOT NULL REFERENCES warehouse.dim_plan (plan_key),
    plan_id SMALLINT NOT NULL,
    state CHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    enrollment_date DATE NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE NOT NULL,
    is_current BOOLEAN NOT NULL,
    CONSTRAINT dim_member_gender_ck CHECK (gender IN ('F', 'M', 'X', 'U')),
    CONSTRAINT dim_member_dates_ck CHECK (effective_end >= effective_start),
    CONSTRAINT uq_dim_member_version UNIQUE (member_id, effective_start)
);

-- Date-range lookup used by the fact load: member + service date -> one version.
CREATE INDEX IF NOT EXISTS idx_dim_member_scd_lookup
    ON warehouse.dim_member (member_id, effective_start, effective_end);

-- Physical guarantee that the SCD verification query stays empty.
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_member_one_current
    ON warehouse.dim_member (member_id)
    WHERE is_current;

COMMENT ON TABLE warehouse.dim_member IS
    'Conformed SCD Type 2 member dimension. member_id -1 / member_key -1 is Not Applicable and is not a real member.';
COMMENT ON COLUMN warehouse.dim_member.plan_id IS
    'Tracked natural key. Compared with IS DISTINCT FROM during change detection. plan_key is the warehouse foreign key.';
COMMENT ON COLUMN warehouse.dim_member.effective_end IS
    'Inclusive end date. The open version uses 9999-12-31. The close step sets this to the next version start minus one day.';
