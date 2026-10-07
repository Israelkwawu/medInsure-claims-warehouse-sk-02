-- Role-playing calendar. fact_claim uses it twice (service date and processed
-- date) through two foreign keys. A future fact_pharmacy table uses this same
-- dimension. BIGSERIAL is the surrogate required by the standard; calendar_date
-- is the business key analysts think in.
CREATE TABLE IF NOT EXISTS warehouse.dim_date (
    date_key BIGSERIAL PRIMARY KEY,
    calendar_date DATE,
    year_number SMALLINT NOT NULL,
    quarter_number SMALLINT NOT NULL,
    month_number SMALLINT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    day_of_month SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    week_of_year SMALLINT NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    year_month VARCHAR(7) NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_date_calendar_date
    ON warehouse.dim_date (calendar_date);

COMMENT ON TABLE warehouse.dim_date IS
    'Conformed calendar, 2020-01-01 through 2030-12-31, plus the Not Applicable row (date_key -1, calendar_date null).';
COMMENT ON COLUMN warehouse.dim_date.date_key IS
    'Surrogate. Role-playing facts store this key more than once rather than aliasing the table in the physical model.';
