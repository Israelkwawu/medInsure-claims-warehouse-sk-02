-- Supports provider-period paid aggregates (queries 1 and 8). The single-column
-- provider_key index remains because every foreign key is indexed on its own.
-- Query 6 is not given a second covering index; the monthly materialized view
-- replaces that scan.
CREATE INDEX IF NOT EXISTS idx_fact_claim_provider_service_paid
    ON warehouse.fact_claim (provider_key, service_date_key)
    INCLUDE (total_paid, claim_status);
