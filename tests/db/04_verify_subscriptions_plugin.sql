-- ============================================================================
-- TEST SUITE: 04_VERIFY_SUBSCRIPTIONS_PLUGIN.SQL
-- Description: Verification for Subscriptions & Billing plugin schema and RLS
-- ============================================================================

DO $$
DECLARE
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY['plans', 'subscriptions', 'usage_meters'];
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema billing and tables...';
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'billing') THEN
        RAISE EXCEPTION 'FAILED: Schema billing does not exist!';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'billing' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing tables in schema billing: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 3 Billing Tables exist in schema billing.';
    END IF;

    RAISE NOTICE '>>> [TEST 2] Verifying RLS on billing tables...';
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = 'billing' AND tablename = v_tbl AND rowsecurity = true
        ) THEN
            RAISE EXCEPTION 'FAILED: RLS is disabled on billing.%!', v_tbl;
        END IF;
    END LOOP;
    RAISE NOTICE ' [PASS] RLS is active on 100%% of schema billing tables.';

    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry entry...';
    IF NOT EXISTS (SELECT 1 FROM public.system_plugins WHERE id = 'subscriptions' AND status = 'installed') THEN
        RAISE EXCEPTION 'FAILED: Plugin subscriptions is not registered as installed!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin subscriptions is active in public.system_plugins.';
    END IF;

    RAISE NOTICE '>>> [TEST 4] Verifying Billing Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'billing') < 3 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 3 billing permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 3 Billing permissions registered successfully.';
    END IF;
END $$;
