-- Synthetic ICD-10 style codes. The letter and the numeric quotient together are
-- unique for i in 1..12000, so the diagnosis primary key cannot collide.
CREATE OR REPLACE FUNCTION source.make_icd10(i integer)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT substr('ABCDEFGHIJKLMNOPQR', 1 + ((i - 1) % 18), 1)
        || lpad((((i - 1) / 18) % 100)::text, 2, '0')
        || '.'
        || lpad(((i - 1) / 18)::text, 3, '0')
$$;

CREATE OR REPLACE FUNCTION source.icd10_category(letter text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE letter
        WHEN 'A' THEN 'Infectious and parasitic diseases'
        WHEN 'B' THEN 'Neoplasms'
        WHEN 'C' THEN 'Endocrine and metabolic diseases'
        WHEN 'D' THEN 'Mental and behavioral disorders'
        WHEN 'E' THEN 'Diseases of the nervous system'
        WHEN 'F' THEN 'Diseases of the eye'
        WHEN 'G' THEN 'Diseases of the ear'
        WHEN 'H' THEN 'Diseases of the circulatory system'
        WHEN 'I' THEN 'Diseases of the respiratory system'
        WHEN 'J' THEN 'Diseases of the digestive system'
        WHEN 'K' THEN 'Diseases of the skin'
        WHEN 'L' THEN 'Diseases of the musculoskeletal system'
        WHEN 'M' THEN 'Diseases of the genitourinary system'
        WHEN 'N' THEN 'Pregnancy and childbirth'
        WHEN 'O' THEN 'Perinatal conditions'
        WHEN 'P' THEN 'Congenital conditions'
        WHEN 'Q' THEN 'Symptoms and abnormal findings'
        ELSE 'Factors influencing health status'
    END
$$;

-- p_scale = 1 builds the spec volumes (500k members, 15k providers, 2M claims).
-- Smaller scales keep the same shape, the full code catalogs, and the planted
-- defects used by the dead-letter path and the data-quality checks:
--   claim_id % 1000 = 0 -> unknown member
--   claim_id % 1000 = 1 -> unknown provider
--   claim_id % 4000 = 2 and line 1 -> procedure code ZZZZZ
--   eight claims on the last provider, whose network date is 2030-01-01
CREATE OR REPLACE PROCEDURE source.generate_synthetic_data(p_scale numeric DEFAULT 1)
LANGUAGE plpgsql
AS $$
DECLARE
    v_members integer;
    v_providers integer;
    v_claims integer;
BEGIN
    IF p_scale <= 0 OR p_scale > 1 THEN
        RAISE EXCEPTION 'p_scale must be in the range (0, 1]';
    END IF;

    SET LOCAL statement_timeout = 0;

    v_members := GREATEST(500, round(500000 * p_scale)::integer);
    v_providers := GREATEST(50, round(15000 * p_scale)::integer);
    v_claims := GREATEST(2000, round(2000000 * p_scale)::integer);

    TRUNCATE TABLE
        source.claim_lines,
        source.claims,
        source.provider_network_history,
        source.providers,
        source.member_plan_history,
        source.members,
        source.diagnosis_codes,
        source.procedure_codes,
        source.plan_types
    RESTART IDENTITY;

    INSERT INTO source.plan_types (
        plan_id, plan_code, plan_name, plan_type, deductible, oop_max, coinsurance_pct
    )
    VALUES
        (1, 'HMO-BAS', 'HMO Basic', 'HMO', 1500, 5000, 20),
        (2, 'HMO-PLS', 'HMO Plus', 'HMO', 500, 3000, 10),
        (3, 'PPO-STD', 'PPO Standard', 'PPO', 2000, 6500, 20),
        (4, 'PPO-PRM', 'PPO Premium', 'PPO', 1000, 4500, 10),
        (5, 'EPO-ESS', 'EPO Essential', 'EPO', 1000, 5000, 15),
        (6, 'EPO-CHO', 'EPO Choice', 'EPO', 500, 3500, 10),
        (7, 'HDHP-BRZ', 'HDHP Bronze', 'HDHP', 3500, 7000, 20),
        (8, 'HDHP-SLV', 'HDHP Silver', 'HDHP', 2500, 6000, 10);

    INSERT INTO source.diagnosis_codes (diagnosis_code, description, category_code, category_name)
    SELECT
        source.make_icd10(gs),
        'Synthetic diagnosis ' || source.make_icd10(gs),
        substr(source.make_icd10(gs), 1, 3),
        source.icd10_category(substr(source.make_icd10(gs), 1, 1))
    FROM generate_series(1, 12000) AS gs;

    INSERT INTO source.procedure_codes (procedure_code, description, category_name)
    SELECT
        lpad((10000 + gs)::text, 5, '0'),
        'Synthetic procedure ' || lpad((10000 + gs)::text, 5, '0'),
        CASE
            WHEN gs <= 1500 THEN 'Evaluation and Management'
            WHEN gs <= 2500 THEN 'Anesthesia'
            WHEN gs <= 5000 THEN 'Surgery'
            WHEN gs <= 6500 THEN 'Radiology'
            WHEN gs <= 7500 THEN 'Pathology and Laboratory'
            ELSE 'Medicine'
        END
    FROM generate_series(1, 8500) AS gs;

    INSERT INTO source.members (
        member_id, first_name, last_name, date_of_birth, gender,
        plan_id, state, zip_code, enrollment_date
    )
    SELECT
        gs,
        (ARRAY['Ava','Liam','Mia','Noah','Zoe','Ethan','Lila','Owen','Nora','Jude','Aria','Leo'])[1 + (gs % 12)],
        (ARRAY['Nguyen','Patel','Garcia','Kim','Singh','Brown','Martinez','Johnson','Davis','Wilson','Anderson','Thomas'])[1 + ((gs / 12) % 12)],
        DATE '1955-01-01' + (gs % 18000),
        (ARRAY['F','M','F','M','X'])[1 + (gs % 5)],
        (1 + (gs % 8))::smallint,
        loc.state,
        lpad((10000 + (gs % 80000))::text, 5, '0'),
        DATE '2020-01-01' + (gs % 1600)
    FROM generate_series(1, v_members) AS gs
    JOIN (
        VALUES
            (0, 'TX'), (1, 'CA'), (2, 'FL'), (3, 'NY'), (4, 'IL'),
            (5, 'PA'), (6, 'OH'), (7, 'GA'), (8, 'NC'), (9, 'MI')
    ) AS loc(location_id, state)
        ON loc.location_id = (gs % 10);

    -- Version 1 is the enrollment snapshot. Even member ids get a second version.
    -- 500k members + 250k changes = 750k history rows at full scale.
    INSERT INTO source.member_plan_history (
        member_id, plan_id, state, zip_code, effective_start, effective_end
    )
    SELECT
        member_id,
        plan_id,
        state,
        zip_code,
        enrollment_date,
        CASE
            WHEN member_id % 2 = 0 THEN (enrollment_date + 200 + (member_id % 300)::integer) - 1
            ELSE NULL
        END
    FROM source.members;

    INSERT INTO source.member_plan_history (
        member_id, plan_id, state, zip_code, effective_start, effective_end
    )
    SELECT
        member_id,
        (1 + (plan_id % 8))::smallint,
        CASE WHEN member_id % 4 = 0 THEN 'WA' ELSE state END,
        lpad((((substring(zip_code FROM 1 FOR 5))::integer + 17) % 90000 + 10000)::text, 5, '0'),
        enrollment_date + 200 + (member_id % 300)::integer,
        NULL
    FROM source.members
    WHERE member_id % 2 = 0;

    UPDATE source.members AS m
    SET
        plan_id = h.plan_id,
        state = h.state,
        zip_code = h.zip_code
    FROM source.member_plan_history AS h
    WHERE h.member_id = m.member_id
      AND h.effective_end IS NULL;

    INSERT INTO source.providers (
        provider_id, npi, provider_name, provider_type, specialty,
        network_status, city, state, network_effective_date
    )
    SELECT
        gs,
        lpad(gs::text, 10, '0'),
        CASE
            WHEN gs % 15 = 0 THEN 'Regional Hospital ' || gs::text
            WHEN gs % 7 = 0 THEN 'Community Facility ' || gs::text
            ELSE
                (ARRAY['Avery','Blake','Cameron','Drew','Ellis','Finley','Gray','Harper','Indigo','Jordan'])[1 + (gs % 10)]
                || ' '
                || (ARRAY['Clinic','Medical Group','Specialty','Practice','Associates'])[1 + ((gs / 10) % 5)]
        END,
        CASE
            WHEN gs % 15 = 0 THEN 'Hospital'
            WHEN gs % 7 = 0 THEN 'Facility'
            ELSE 'Physician'
        END,
        (ARRAY['Cardiology','Orthopedics','Pediatrics','Internal Medicine','Radiology','Emergency Medicine','General Surgery','Oncology','Family Medicine','Psychiatry','Dermatology','Ophthalmology'])[1 + ((gs + 3) % 12)],
        CASE WHEN gs % 5 = 0 THEN 'Out-of-Network' ELSE 'In-Network' END,
        loc.city,
        loc.state,
        DATE '2019-01-01'
    FROM generate_series(1, v_providers) AS gs
    JOIN (
        VALUES
            (0, 'Austin', 'TX'),
            (1, 'San Diego', 'CA'),
            (2, 'Miami', 'FL'),
            (3, 'Buffalo', 'NY'),
            (4, 'Chicago', 'IL'),
            (5, 'Pittsburgh', 'PA'),
            (6, 'Columbus', 'OH'),
            (7, 'Atlanta', 'GA'),
            (8, 'Raleigh', 'NC'),
            (9, 'Detroit', 'MI')
    ) AS loc(location_id, city, state)
        ON loc.location_id = (gs % 10);

    -- Last provider is reserved for the anachronism check and is not used by the random claim draw.
    UPDATE source.providers
    SET
        provider_name = 'Northstar Family Medicine',
        provider_type = 'Physician',
        specialty = 'Family Medicine',
        network_status = 'In-Network',
        city = 'Austin',
        state = 'TX',
        network_effective_date = DATE '2030-01-01'
    WHERE provider_id = v_providers;

    INSERT INTO source.provider_network_history (
        provider_id, network_status, specialty, effective_start, effective_end, network_effective_date
    )
    SELECT
        provider_id,
        network_status,
        specialty,
        DATE '2019-01-01',
        CASE
            WHEN provider_id % 2 = 0 AND provider_id <> v_providers
            THEN (DATE '2021-01-01' + (provider_id % 180)::integer) - 1
            ELSE NULL
        END,
        network_effective_date
    FROM source.providers;

    INSERT INTO source.provider_network_history (
        provider_id, network_status, specialty, effective_start, effective_end, network_effective_date
    )
    SELECT
        p.provider_id,
        CASE
            WHEN p.provider_id % 4 = 0 AND p.network_status = 'In-Network' THEN 'Out-of-Network'
            WHEN p.provider_id % 4 = 0 THEN 'In-Network'
            ELSE p.network_status
        END,
        (ARRAY['Cardiology','Orthopedics','Pediatrics','Internal Medicine','Radiology','Emergency Medicine','General Surgery','Oncology','Family Medicine','Psychiatry','Dermatology','Ophthalmology'])[1 + (p.provider_id % 12)::integer],
        DATE '2021-01-01' + (p.provider_id % 180)::integer,
        NULL,
        CASE
            WHEN p.provider_id % 4 = 0 THEN DATE '2021-01-01' + (p.provider_id % 180)::integer
            ELSE p.network_effective_date
        END
    FROM source.providers AS p
    WHERE p.provider_id % 2 = 0
      AND p.provider_id <> v_providers;

    UPDATE source.providers AS p
    SET
        network_status = h.network_status,
        specialty = h.specialty,
        network_effective_date = h.network_effective_date
    FROM source.provider_network_history AS h
    WHERE h.provider_id = p.provider_id
      AND h.effective_end IS NULL;

    PERFORM setseed(0.42);

    INSERT INTO source.claims (
        claim_id, member_id, provider_id, primary_diagnosis_code,
        claim_type, claim_status, denial_reason, service_date, processed_date,
        total_billed, total_allowed, total_paid
    )
    SELECT
        drafted.claim_id,
        drafted.member_id,
        drafted.provider_id,
        source.make_icd10((1 + (drafted.claim_id % 12000))::integer),
        CASE
            WHEN drafted.claim_id % 25 = 0 THEN 'Inpatient'
            WHEN drafted.claim_id % 7 = 0 THEN 'Emergency'
            WHEN drafted.claim_id % 3 = 0 THEN 'Outpatient'
            ELSE 'Professional'
        END,
        CASE WHEN drafted.claim_id % 20 = 0 THEN 'Denied' ELSE 'Paid' END,
        CASE
            WHEN drafted.claim_id % 20 = 0 THEN
                (ARRAY['Medical necessity','Duplicate claim','Timely filing','Not a covered benefit','Missing authorization'])[(1 + ((drafted.claim_id / 20) % 5))::integer]
            ELSE NULL
        END,
        drafted.service_date,
        LEAST(drafted.service_date + (drafted.claim_id % 10)::integer, DATE '2026-10-06'),
        0,
        0,
        0
    FROM (
        SELECT
            gs AS claim_id,
            CASE
                WHEN gs % 1000 = 0 THEN 0
                ELSE 1 + ((gs * 13) % v_members)
            END AS member_id,
            CASE
                WHEN gs % 1000 = 1 THEN 0
                ELSE 1 + floor(power(random(), 3) * (v_providers - 1))::integer
            END AS provider_id,
            anchor.enrollment_date + (
                (gs * 17) % GREATEST((DATE '2026-09-30' - anchor.enrollment_date), 1)
            ) AS service_date
        FROM generate_series(1, v_claims) AS gs
        JOIN source.members AS anchor
            ON anchor.member_id = CASE
                WHEN gs % 1000 = 0 THEN 1
                ELSE 1 + ((gs * 13) % v_members)
            END
    ) AS drafted;

    INSERT INTO source.claims (
        claim_id, member_id, provider_id, primary_diagnosis_code,
        claim_type, claim_status, denial_reason, service_date, processed_date,
        total_billed, total_allowed, total_paid
    )
    SELECT
        v_claims + gs,
        gs,
        v_providers,
        source.make_icd10(gs),
        'Professional',
        'Paid',
        NULL,
        DATE '2024-06-01',
        DATE '2024-06-05',
        0,
        0,
        0
    FROM generate_series(1, 8) AS gs;

    INSERT INTO source.claim_lines (
        claim_line_id, claim_id, line_number, procedure_code, diagnosis_code,
        service_date, units, billed_amount, allowed_amount, paid_amount
    )
    SELECT
        c.claim_id * 10 + gs.line_number,
        c.claim_id,
        gs.line_number::smallint,
        CASE
            WHEN c.claim_id % 4000 = 2 AND gs.line_number = 1 THEN 'ZZZZZ'
            ELSE lpad((10001 + ((c.claim_id + gs.line_number) % 8500))::text, 5, '0')
        END,
        source.make_icd10((1 + ((c.claim_id + gs.line_number) % 12000))::integer),
        c.service_date,
        (1 + (gs.line_number % 3))::numeric(6, 2),
        amounts.billed,
        amounts.allowed,
        CASE
            WHEN c.claim_status = 'Denied' THEN 0
            ELSE round(amounts.allowed * 0.85, 2)
        END
    FROM source.claims AS c
    JOIN generate_series(1, 4) AS gs(line_number)
        ON gs.line_number <= CASE WHEN c.claim_id % 4 = 0 THEN 3 ELSE 4 END
    CROSS JOIN LATERAL (
        SELECT round((
            CASE
                WHEN c.claim_type = 'Inpatient' THEN 1800 + (c.claim_id % 9000)
                WHEN c.claim_type = 'Emergency' THEN 400 + (c.claim_id % 2000)
                ELSE 50 + (c.claim_id % 450)
            END
        )::numeric, 2) AS billed
    ) AS raw
    CROSS JOIN LATERAL (
        SELECT raw.billed AS billed, round(raw.billed * 0.72, 2) AS allowed
    ) AS amounts;

    UPDATE source.claims AS c
    SET
        total_billed = rolled.billed,
        total_allowed = rolled.allowed,
        total_paid = rolled.paid
    FROM (
        SELECT
            claim_id,
            SUM(billed_amount) AS billed,
            SUM(allowed_amount) AS allowed,
            SUM(paid_amount) AS paid
        FROM source.claim_lines
        GROUP BY claim_id
    ) AS rolled
    WHERE rolled.claim_id = c.claim_id;

    INSERT INTO audit.load_profile (
        profile_id, scale_factor, member_count, provider_count, claim_count, claim_line_count, generated_at
    )
    VALUES (
        1,
        p_scale,
        (SELECT COUNT(*) FROM source.members),
        (SELECT COUNT(*) FROM source.providers),
        (SELECT COUNT(*) FROM source.claims),
        (SELECT COUNT(*) FROM source.claim_lines),
        now()
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET
        scale_factor = EXCLUDED.scale_factor,
        member_count = EXCLUDED.member_count,
        provider_count = EXCLUDED.provider_count,
        claim_count = EXCLUDED.claim_count,
        claim_line_count = EXCLUDED.claim_line_count,
        generated_at = EXCLUDED.generated_at;

    ANALYZE source.members;
    ANALYZE source.member_plan_history;
    ANALYZE source.providers;
    ANALYZE source.provider_network_history;
    ANALYZE source.claims;
    ANALYZE source.claim_lines;
    ANALYZE source.diagnosis_codes;
    ANALYZE source.procedure_codes;

    RAISE NOTICE 'Generated scale %: % members, % providers, % claims, % lines',
        p_scale,
        (SELECT COUNT(*) FROM source.members),
        (SELECT COUNT(*) FROM source.providers),
        (SELECT COUNT(*) FROM source.claims),
        (SELECT COUNT(*) FROM source.claim_lines);
END;
$$;
