-- ============================================================================
-- TEST SUITE: 02C_VERIFY_CLOUD_BROWSERS.SQL
-- Description: Verification for Central Cloud Browsers, Fingerprint & Storage Sync
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying runners.browsers table and schema...';
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'runners' AND table_name = 'browsers'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table runners.browsers does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Table runners.browsers exists in schema runners.';
    END IF;

    -- Verify Key Columns for GoLogin-style profile
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'runners' AND table_name = 'browsers' AND column_name = 'fingerprint_seed'
    ) THEN
        RAISE EXCEPTION 'FAILED: Column fingerprint_seed missing from runners.browsers!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'runners' AND table_name = 'browsers' AND column_name = 'storage_path'
    ) THEN
        RAISE EXCEPTION 'FAILED: Column storage_path missing from runners.browsers!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'runners' AND table_name = 'browsers' AND column_name = 'locked_by_device_id'
    ) THEN
        RAISE EXCEPTION 'FAILED: Column locked_by_device_id missing from runners.browsers!';
    END IF;

    RAISE NOTICE ' [PASS] All core columns (fingerprint_seed, storage_path, locked_by_device_id) verified.';

    -- Verify RLS is enabled on runners.browsers
    RAISE NOTICE '>>> [TEST 2] Verifying Row Level Security on runners.browsers...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'runners' AND tablename = 'browsers' AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on runners.browsers!';
    ELSE
        RAISE NOTICE ' [PASS] RLS is active on runners.browsers.';
    END IF;

    -- Verify RPC functions
    RAISE NOTICE '>>> [TEST 3] Verifying Lease Locking RPCs...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'runners' AND p.proname = 'acquire_browser'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC runners.acquire_browser does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'runners' AND p.proname = 'release_browser'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC runners.release_browser does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Distributed lease RPCs acquire_browser and release_browser verified.';
    END IF;

    -- Verify browser-profiles storage bucket
    RAISE NOTICE '>>> [TEST 4] Verifying browser-profiles bucket configuration...';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'browser-profiles') THEN
            RAISE EXCEPTION 'FAILED: Storage bucket browser-profiles does not exist!';
        ELSE
            RAISE NOTICE ' [PASS] Supabase Storage bucket browser-profiles is configured.';
        END IF;
    END IF;

    -- Verify Permissions count
    RAISE NOTICE '>>> [TEST 5] Verifying Runners Permissions count...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'runners') < 7 THEN
        RAISE EXCEPTION 'FAILED: Expected at least 7 runners permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All Runners permissions registered successfully.';
    END IF;
END $$;
