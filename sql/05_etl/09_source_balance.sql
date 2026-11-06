-- One disposition for every source row. audit.source_balance adds those
-- dispositions up. A row is unaccounted when none of the named outcomes fit.
-- warehouse_only is a warehouse row with no source parent, other than the
-- Not Applicable key -1.

CREATE OR REPLACE VIEW audit.claim_disposition AS
SELECT
    c.claim_id,
    c.claim_id::text AS source_key,
    CASE
        WHEN loaded.claim_id IS NOT NULL AND rejected.source_key IS NOT NULL THEN 'conflict'
        WHEN loaded.claim_id IS NOT NULL THEN 'loaded'
        WHEN rejected.source_key IS NOT NULL THEN 'rejected'
        ELSE 'unaccounted'
    END AS disposition,
    rejected.reject_reason
FROM source.claims AS c
LEFT JOIN warehouse.fact_claim AS loaded
    ON loaded.claim_id = c.claim_id
LEFT JOIN LATERAL (
    SELECT source_key, reject_reason
    FROM audit.etl_dead_letter
    WHERE pipeline_name = 'fact_claim'
      AND source_key = c.claim_id::text
    ORDER BY dead_letter_id DESC
    LIMIT 1
) AS rejected ON TRUE;

COMMENT ON VIEW audit.claim_disposition IS
    'Every source claim is loaded, rejected, or unaccounted. Loaded and rejected together is a conflict.';

CREATE OR REPLACE VIEW audit.claim_line_disposition AS
SELECT
    line.claim_line_id,
    line.claim_id,
    line.line_number,
    line.claim_line_id::text AS source_key,
    CASE
        WHEN placed.claim_line_key IS NOT NULL
         AND (line_reject.source_key IS NOT NULL OR header_reject.source_key IS NOT NULL)
            THEN 'conflict'
        WHEN placed.claim_line_key IS NOT NULL THEN 'loaded'
        WHEN line_reject.source_key IS NOT NULL THEN 'rejected'
        WHEN header_reject.source_key IS NOT NULL THEN 'held_with_header'
        ELSE 'unaccounted'
    END AS disposition,
    COALESCE(line_reject.reject_reason, header_reject.reject_reason) AS reject_reason
FROM source.claim_lines AS line
LEFT JOIN warehouse.fact_claim_line AS placed
    ON placed.claim_id = line.claim_id
   AND placed.line_number = line.line_number
LEFT JOIN LATERAL (
    SELECT source_key, reject_reason
    FROM audit.etl_dead_letter
    WHERE pipeline_name = 'fact_claim_line'
      AND source_key = line.claim_line_id::text
    ORDER BY dead_letter_id DESC
    LIMIT 1
) AS line_reject ON TRUE
LEFT JOIN LATERAL (
    SELECT source_key, reject_reason
    FROM audit.etl_dead_letter
    WHERE pipeline_name = 'fact_claim'
      AND source_key = line.claim_id::text
    ORDER BY dead_letter_id DESC
    LIMIT 1
) AS header_reject ON TRUE;

COMMENT ON VIEW audit.claim_line_disposition IS
    'Every source service line is loaded, written to the dead-letter log, or unaccounted. A line of a rejected header is rejected, with the header reason.';

CREATE OR REPLACE VIEW audit.member_history_disposition AS
SELECT
    h.history_id,
    h.member_id,
    h.history_id::text AS source_key,
    CASE
        WHEN opened.member_key IS NOT NULL THEN 'loaded'
        WHEN collapsed.member_key IS NOT NULL THEN 'collapsed'
        ELSE 'unaccounted'
    END AS disposition
FROM source.member_plan_history AS h
LEFT JOIN warehouse.dim_member AS opened
    ON opened.member_id = h.member_id
   AND opened.member_key <> -1
   AND opened.effective_start = h.effective_start
LEFT JOIN LATERAL (
    SELECT d.member_key
    FROM warehouse.dim_member AS d
    WHERE opened.member_key IS NULL
      AND d.member_id = h.member_id
      AND d.member_key <> -1
      AND h.effective_start BETWEEN d.effective_start AND d.effective_end
      AND d.plan_id IS NOT DISTINCT FROM h.plan_id
      AND d.state IS NOT DISTINCT FROM h.state
      AND d.zip_code IS NOT DISTINCT FROM h.zip_code
    LIMIT 1
) AS collapsed ON TRUE;

COMMENT ON VIEW audit.member_history_disposition IS
    'A history row is loaded when it opened a member version. It is collapsed when plan, state, and zip already match the version that covers its start date.';

CREATE OR REPLACE VIEW audit.provider_history_disposition AS
SELECT
    h.history_id,
    h.provider_id,
    h.history_id::text AS source_key,
    CASE
        WHEN opened.provider_key IS NOT NULL THEN 'loaded'
        WHEN collapsed.provider_key IS NOT NULL THEN 'collapsed'
        ELSE 'unaccounted'
    END AS disposition
FROM source.provider_network_history AS h
LEFT JOIN warehouse.dim_provider AS opened
    ON opened.provider_id = h.provider_id
   AND opened.provider_key <> -1
   AND opened.effective_start = h.effective_start
LEFT JOIN LATERAL (
    SELECT d.provider_key
    FROM warehouse.dim_provider AS d
    WHERE opened.provider_key IS NULL
      AND d.provider_id = h.provider_id
      AND d.provider_key <> -1
      AND h.effective_start BETWEEN d.effective_start AND d.effective_end
      AND d.network_status IS NOT DISTINCT FROM h.network_status
      AND d.specialty IS NOT DISTINCT FROM h.specialty
    LIMIT 1
) AS collapsed ON TRUE;

COMMENT ON VIEW audit.provider_history_disposition IS
    'A history row is loaded when it opened a provider version. It is collapsed when network status and specialty already match the version that covers its start date.';

CREATE OR REPLACE VIEW audit.source_balance AS
SELECT
    1 AS sort_order,
    'plan_types' AS entity,
    COUNT(*) AS source_rows,
    COUNT(*) FILTER (WHERE dim.plan_id IS NOT NULL) AS loaded,
    0::bigint AS rejected,
    0::bigint AS held_with_header,
    0::bigint AS collapsed,
    0::bigint AS conflict,
    COUNT(*) FILTER (WHERE dim.plan_id IS NULL) AS unaccounted,
    (
        SELECT COUNT(*)
        FROM warehouse.dim_plan AS extra
        WHERE extra.plan_key <> -1
          AND NOT EXISTS (
              SELECT 1 FROM source.plan_types AS src WHERE src.plan_id = extra.plan_id
          )
    ) AS warehouse_only
FROM source.plan_types AS src
LEFT JOIN warehouse.dim_plan AS dim
    ON dim.plan_id = src.plan_id
   AND dim.plan_key <> -1

UNION ALL

SELECT
    2,
    'diagnosis_codes',
    COUNT(*),
    COUNT(*) FILTER (WHERE dim.diagnosis_code IS NOT NULL),
    0, 0, 0, 0,
    COUNT(*) FILTER (WHERE dim.diagnosis_code IS NULL),
    (
        SELECT COUNT(*)
        FROM warehouse.dim_diagnosis AS extra
        WHERE extra.diagnosis_key <> -1
          AND NOT EXISTS (
              SELECT 1
              FROM source.diagnosis_codes AS src
              WHERE src.diagnosis_code = extra.diagnosis_code
          )
    )
FROM source.diagnosis_codes AS src
LEFT JOIN warehouse.dim_diagnosis AS dim
    ON dim.diagnosis_code = src.diagnosis_code
   AND dim.diagnosis_key <> -1

UNION ALL

SELECT
    3,
    'procedure_codes',
    COUNT(*),
    COUNT(*) FILTER (WHERE dim.procedure_code IS NOT NULL),
    0, 0, 0, 0,
    COUNT(*) FILTER (WHERE dim.procedure_code IS NULL),
    (
        SELECT COUNT(*)
        FROM warehouse.dim_procedure AS extra
        WHERE extra.procedure_key <> -1
          AND NOT EXISTS (
              SELECT 1
              FROM source.procedure_codes AS src
              WHERE src.procedure_code = extra.procedure_code
          )
    )
FROM source.procedure_codes AS src
LEFT JOIN warehouse.dim_procedure AS dim
    ON dim.procedure_code = src.procedure_code
   AND dim.procedure_key <> -1

UNION ALL

SELECT
    4,
    'members',
    COUNT(*),
    COUNT(*) FILTER (WHERE dim.member_id IS NOT NULL),
    0, 0, 0, 0,
    COUNT(*) FILTER (WHERE dim.member_id IS NULL),
    (
        SELECT COUNT(DISTINCT extra.member_id)
        FROM warehouse.dim_member AS extra
        WHERE extra.member_key <> -1
          AND NOT EXISTS (
              SELECT 1 FROM source.members AS src WHERE src.member_id = extra.member_id
          )
    )
FROM source.members AS src
LEFT JOIN (
    SELECT DISTINCT member_id
    FROM warehouse.dim_member
    WHERE member_key <> -1
) AS dim ON dim.member_id = src.member_id

UNION ALL

SELECT
    5,
    'member_plan_history',
    COUNT(*),
    COUNT(*) FILTER (WHERE disposition = 'loaded'),
    0, 0,
    COUNT(*) FILTER (WHERE disposition = 'collapsed'),
    0,
    COUNT(*) FILTER (WHERE disposition = 'unaccounted'),
    (
        SELECT COUNT(*)
        FROM warehouse.dim_member AS extra
        WHERE extra.member_key <> -1
          AND NOT EXISTS (
              SELECT 1
              FROM source.member_plan_history AS src
              WHERE src.member_id = extra.member_id
                AND src.effective_start = extra.effective_start
          )
    )
FROM audit.member_history_disposition

UNION ALL

SELECT
    6,
    'providers',
    COUNT(*),
    COUNT(*) FILTER (WHERE dim.provider_id IS NOT NULL),
    0, 0, 0, 0,
    COUNT(*) FILTER (WHERE dim.provider_id IS NULL),
    (
        SELECT COUNT(DISTINCT extra.provider_id)
        FROM warehouse.dim_provider AS extra
        WHERE extra.provider_key <> -1
          AND NOT EXISTS (
              SELECT 1 FROM source.providers AS src WHERE src.provider_id = extra.provider_id
          )
    )
FROM source.providers AS src
LEFT JOIN (
    SELECT DISTINCT provider_id
    FROM warehouse.dim_provider
    WHERE provider_key <> -1
) AS dim ON dim.provider_id = src.provider_id

UNION ALL

SELECT
    7,
    'provider_network_history',
    COUNT(*),
    COUNT(*) FILTER (WHERE disposition = 'loaded'),
    0, 0,
    COUNT(*) FILTER (WHERE disposition = 'collapsed'),
    0,
    COUNT(*) FILTER (WHERE disposition = 'unaccounted'),
    (
        SELECT COUNT(*)
        FROM warehouse.dim_provider AS extra
        WHERE extra.provider_key <> -1
          AND NOT EXISTS (
              SELECT 1
              FROM source.provider_network_history AS src
              WHERE src.provider_id = extra.provider_id
                AND src.effective_start = extra.effective_start
          )
    )
FROM audit.provider_history_disposition

UNION ALL

SELECT
    8,
    'claims',
    COUNT(*),
    COUNT(*) FILTER (WHERE disposition = 'loaded'),
    COUNT(*) FILTER (WHERE disposition = 'rejected'),
    0, 0,
    COUNT(*) FILTER (WHERE disposition = 'conflict'),
    COUNT(*) FILTER (WHERE disposition = 'unaccounted'),
    (
        SELECT COUNT(*)
        FROM warehouse.fact_claim AS extra
        WHERE NOT EXISTS (
            SELECT 1 FROM source.claims AS src WHERE src.claim_id = extra.claim_id
        )
    )
FROM audit.claim_disposition

UNION ALL

SELECT
    9,
    'claim_lines',
    COUNT(*),
    COUNT(*) FILTER (WHERE disposition = 'loaded'),
    COUNT(*) FILTER (WHERE disposition = 'rejected'),
    COUNT(*) FILTER (WHERE disposition = 'held_with_header'),
    0,
    COUNT(*) FILTER (WHERE disposition = 'conflict'),
    COUNT(*) FILTER (WHERE disposition = 'unaccounted'),
    (
        SELECT COUNT(*)
        FROM warehouse.fact_claim_line AS extra
        WHERE NOT EXISTS (
            SELECT 1
            FROM source.claim_lines AS src
            WHERE src.claim_id = extra.claim_id
              AND src.line_number = extra.line_number
        )
    )
FROM audit.claim_line_disposition;

COMMENT ON VIEW audit.source_balance IS
    'Source row counts by disposition. source_rows equals loaded + rejected + held_with_header + collapsed + conflict + unaccounted. The Not Applicable dimension row is excluded from warehouse_only.';
