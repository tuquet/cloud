-- ============================================================================
-- TEST SUITE: 03_VERIFY_BROWSERS_PLUGIN.SQL
-- Description: Verification for Dedicated browsers Schema, Releases Catalog,
--              Antidetect Profiles v2, and Fingerprint Templates
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema browsers...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.schemata WHERE schema_name = 'browsers'
    ) THEN
        RAISE EXCEPTION 'FAILED: Schema browsers does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Schema browsers exists.';
    END IF;

    -- ========================================================================
    -- TEST 2: browsers.releases (Engine Catalog)
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 2] Verifying browsers.releases table and public catalog...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'browsers' AND table_name = 'releases'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table browsers.releases does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM browsers.releases WHERE version = '148.0.7778.215' AND os_platform = 'windows'
    ) THEN
        RAISE EXCEPTION 'FAILED: Seed release for Windows Chromium 148 is missing!';
    ELSE
        RAISE NOTICE ' [PASS] Seed release for Windows Chromium 148 verified.';
    END IF;

    -- Verify RLS on releases
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'browsers' AND tablename = 'releases' AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on browsers.releases!';
    ELSE
        RAISE NOTICE ' [PASS] RLS enabled on browsers.releases.';
    END IF;

    -- ========================================================================
    -- TEST 3: browsers.profiles (Antidetect Profiles v2)
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 3] Verifying browsers.profiles and anti-detect columns...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'browsers' AND table_name = 'profiles'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table browsers.profiles does not exist!';
    END IF;

    -- Check critical anti-detect columns
    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'screen_width';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: screen_width missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'canvas_mode';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: canvas_mode missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'sec_ch_ua';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: sec_ch_ua missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'max_touch_points';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: max_touch_points missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'geolocation_mode';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: geolocation_mode missing from browsers.profiles'; END IF;

    RAISE NOTICE ' [PASS] All critical anti-detect columns verified on browsers.profiles.';

    -- Verify RLS on profiles
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables WHERE schemaname = 'browsers' AND tablename = 'profiles' AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on browsers.profiles!';
    ELSE
        RAISE NOTICE ' [PASS] RLS enabled on browsers.profiles.';
    END IF;

    -- ========================================================================
    -- TEST 4: browsers.fingerprint_templates
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 4] Verifying browsers.fingerprint_templates...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'browsers' AND table_name = 'fingerprint_templates'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table browsers.fingerprint_templates does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM browsers.fingerprint_templates WHERE is_system = true AND os_platform = 'windows'
    ) THEN
        RAISE EXCEPTION 'FAILED: System fingerprint template for Windows is missing!';
    ELSE
        RAISE NOTICE ' [PASS] System fingerprint templates verified.';
    END IF;

    -- ========================================================================
    -- TEST 5: Storage Bucket Registration
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 5] Verifying browser-profiles storage bucket...';
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'browser-profiles') THEN
            RAISE EXCEPTION 'FAILED: Storage bucket "browser-profiles" not found!';
        ELSE
            RAISE NOTICE ' [PASS] Storage bucket "browser-profiles" registered.';
        END IF;
    END IF;

    -- ========================================================================
    -- TEST 6: Permissions Dictionary
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 6] Verifying permissions for module "browsers"...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'browsers') < 5 THEN
        RAISE EXCEPTION 'FAILED: Permissions for module "browsers" incomplete!';
    ELSE
        RAISE NOTICE ' [PASS] Permissions for module "browsers" successfully registered.';
    END IF;

    -- ========================================================================
    -- TEST 7: Business Functions
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 7] Verifying lease and lock functions...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'acquire_profile' AND pronamespace = 'browsers'::regnamespace
    ) THEN
        RAISE EXCEPTION 'FAILED: Function browsers.acquire_profile does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'release_profile' AND pronamespace = 'browsers'::regnamespace
    ) THEN
        RAISE EXCEPTION 'FAILED: Function browsers.release_profile does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'reap_stale_profile_locks' AND pronamespace = 'browsers'::regnamespace
    ) THEN
        RAISE EXCEPTION 'FAILED: Function browsers.reap_stale_profile_locks does not exist!';
    END IF;

    RAISE NOTICE ' [PASS] All business logic functions verified.';
    RAISE NOTICE '=============================================================';
    RAISE NOTICE ' [SUCCESS] ALL 7 TESTS FOR BROWSERS PLUGIN PASSED (100%)';
    RAISE NOTICE '=============================================================';
END $$;
