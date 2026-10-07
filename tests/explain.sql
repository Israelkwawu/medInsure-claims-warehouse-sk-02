\pset pager off

\echo ===== Q1 base tables =====
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM warehouse.q01_top_providers_yoy;

\echo ===== Q6 base tables =====
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM warehouse.q06_monthly_volume;

\echo ===== Q6 materialized view =====
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM warehouse.q06_monthly_volume_mv;
