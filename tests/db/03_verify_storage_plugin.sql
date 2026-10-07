-- ============================================================================
-- TEST SUITE: 03_VERIFY_STORAGE_PLUGIN.SQL
-- Description: Verification for Media Storage plugin schema, tables, and RLS
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema media and tables...';
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'media') THEN
        RAISE EXCEPTION 'FAILED: Schema media does not exist!';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'media' AND table_name = 'assets') THEN
        RAISE EXCEPTION 'FAILED: Table media.assets does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Table media.assets exists in schema media.';
    END IF;

    RAISE NOTICE '>>> [TEST 2] Verifying RLS on media.assets...';
    IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'media' AND tablename = 'assets' AND rowsecurity = true) THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on media.assets!';
    ELSE
        RAISE NOTICE ' [PASS] RLS is active on media.assets.';
    END IF;

    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry entry...';
    IF NOT EXISTS (SELECT 1 FROM public.system_plugins WHERE id = 'storage' AND status = 'installed') THEN
        RAISE EXCEPTION 'FAILED: Plugin storage is not registered as installed!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin storage is active in public.system_plugins.';
    END IF;

    RAISE NOTICE '>>> [TEST 4] Verifying Storage Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'media') < 3 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 3 media permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 3 Media permissions registered successfully.';
    END IF;
END $$;
