-- ============================================================================
-- TEST SUITE: 02B_VERIFY_RUNNERS_PLUGIN.SQL
-- Description: Verification for Runners & Compute Fleet schema, tables, and RPCs
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema runners and devices table...';
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'runners') THEN
        RAISE EXCEPTION 'FAILED: Schema runners does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'runners' AND table_name = 'devices'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table runners.devices does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Table runners.devices exists in schema runners.';
    END IF;

    -- Verify RLS is enabled on runners.devices
    RAISE NOTICE '>>> [TEST 2] Verifying Row Level Security (RLS) enforcement...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'runners' AND tablename = 'devices' AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on runners.devices!';
    ELSE
        RAISE NOTICE ' [PASS] RLS is active on runners.devices.';
    END IF;

    -- Verify RPC functions exist
    RAISE NOTICE '>>> [TEST 3] Verifying RPC Functions enroll_device and heartbeat...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'runners' AND p.proname = 'enroll_device'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC function runners.enroll_device does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'runners' AND p.proname = 'heartbeat'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC function runners.heartbeat does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Both RPC functions runners.enroll_device and runners.heartbeat exist.';
    END IF;

    -- Verify Master Plugin Registry Entry
    RAISE NOTICE '>>> [TEST 4] Verifying Plugin Registry entry...';
    IF NOT EXISTS (
        SELECT 1 FROM public.system_plugins WHERE id = 'runners' AND status = 'installed'
    ) THEN
        RAISE EXCEPTION 'FAILED: Plugin runners is not registered as installed in public.system_plugins!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin runners is active in public.system_plugins.';
    END IF;

    -- Verify Atomic Permissions
    RAISE NOTICE '>>> [TEST 5] Verifying Runners Atomic Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'runners') < 3 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 3 runners permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 3 Runners permissions registered successfully.';
    END IF;
END $$;
