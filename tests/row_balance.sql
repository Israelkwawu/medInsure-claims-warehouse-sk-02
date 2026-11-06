-- Every source row has one disposition. Any unaccounted, conflicting, or
-- warehouse-only row fails the run. Held and collapsed rows are named outcomes,
-- so they pass.
CREATE TEMP TABLE test_failures (
    test_name text PRIMARY KEY,
    detail text NOT NULL
);

INSERT INTO test_failures (test_name, detail)
SELECT
    'source balance ' || entity,
    'source ' || source_rows::text
        || ' loaded ' || loaded::text
        || ' rejected ' || rejected::text
        || ' held ' || held_with_header::text
        || ' collapsed ' || collapsed::text
        || ' conflict ' || conflict::text
        || ' unaccounted ' || unaccounted::text
        || ' warehouse_only ' || warehouse_only::text
FROM audit.source_balance
WHERE unaccounted <> 0
   OR conflict <> 0
   OR warehouse_only <> 0
   OR source_rows <> loaded + rejected + held_with_header + collapsed + conflict + unaccounted;

DO $$
DECLARE
    v_count integer;
    v_msg text;
    v_line text;
BEGIN
    FOR v_line IN
        SELECT
            entity || ': source ' || source_rows::text
                || ', loaded ' || loaded::text
                || ', rejected ' || rejected::text
                || ', held ' || held_with_header::text
                || ', collapsed ' || collapsed::text
                || ', unaccounted ' || unaccounted::text
        FROM audit.source_balance
        ORDER BY sort_order
    LOOP
        RAISE NOTICE 'balance %', v_line;
    END LOOP;

    SELECT COUNT(*), string_agg(test_name || ': ' || detail, E'\n' ORDER BY test_name)
    INTO v_count, v_msg
    FROM test_failures;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Source balance failed (%):%', v_count, E'\n' || v_msg;
    END IF;

    RAISE NOTICE 'Source balance passed';
END $$;
