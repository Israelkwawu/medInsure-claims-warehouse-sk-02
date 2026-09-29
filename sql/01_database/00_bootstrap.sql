-- Core namespaces keep source, transformation, warehouse, and audit objects separate.
CREATE SCHEMA IF NOT EXISTS source;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS warehouse;
CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA source IS 'Source OLTP-shaped objects and imported source data.';
COMMENT ON SCHEMA staging IS 'Typed, normalized landing objects used by ETL.';
COMMENT ON SCHEMA warehouse IS 'Dimensional model consumed by analytics.';
COMMENT ON SCHEMA audit IS 'ETL operational logs and rejected records.';