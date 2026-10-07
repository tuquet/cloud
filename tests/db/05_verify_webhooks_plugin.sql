-- ============================================================================
-- TEST SUITE: 05_VERIFY_WEBHOOKS_PLUGIN.SQL
-- Description: Verification for Webhooks & Outbox plugin schema and RLS
-- ============================================================================

DO $$
DECLARE
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY['outbox', 'subscriptions', 'deliveries'];
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema events and tables...';
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'events') THEN
        RAISE EXCEPTION 'FAILED: Schema events does not exist!';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'events' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing tables in schema events: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 3 Events Tables exist in schema events.';
    END IF;

    RAISE NOTICE '>>> [TEST 2] Verifying RLS on events tables...';
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE schemaname = 'events' AND tablename = v_tbl AND rowsecurity = true
        ) THEN
            RAISE EXCEPTION 'FAILED: RLS is disabled on events.%!', v_tbl;
        END IF;
    END LOOP;
    RAISE NOTICE ' [PASS] RLS is active on 100%% of schema events tables.';

    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry entry...';
    IF NOT EXISTS (SELECT 1 FROM public.system_plugins WHERE id = 'webhooks' AND status = 'installed') THEN
        RAISE EXCEPTION 'FAILED: Plugin webhooks is not registered as installed!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin webhooks is active in public.system_plugins.';
    END IF;

    RAISE NOTICE '>>> [TEST 4] Verifying Webhook Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'integrations') < 2 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 2 webhooks permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 2 Webhooks permissions registered successfully.';
    END IF;
END $$;
