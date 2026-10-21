-- ============================================================================
-- TEST SUITE: 03_VERIFY_BROWSERS_PLUGIN.SQL
-- Description: Verification for Dedicated browsers Schema aligned with
--              adryfish/fingerprint-chromium (Ungoogled Chromium Core)
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
    -- TEST 2: browsers.releases (adryfish/fingerprint-chromium Engine Catalog)
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 2] Verifying browsers.releases table and authentic GitHub releases...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'browsers' AND table_name = 'releases'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table browsers.releases does not exist!';
    END IF;

    -- Check required catalog columns
    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'releases' AND column_name = 'asset_name';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: asset_name missing from browsers.releases'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'releases' AND column_name = 'tag';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: tag missing from browsers.releases'; END IF;

    -- Check authentic adryfish GitHub download URL
    IF NOT EXISTS (
        SELECT 1 FROM browsers.releases 
        WHERE version = '148.0.7778.215' 
          AND os_platform = 'windows'
          AND download_url LIKE '%adryfish/fingerprint-chromium%'
          AND asset_name = 'ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip'
    ) THEN
        RAISE EXCEPTION 'FAILED: Authentic adryfish release for Windows Chromium 148 is missing or invalid!';
    ELSE
        RAISE NOTICE ' [PASS] Authentic adryfish release for Windows Chromium 148 verified.';
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
    -- TEST 3: browsers.profiles (Streamlined for C++ adryfish core)
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 3] Verifying browsers.profiles (streamlined, no redundant columns)...';
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'browsers' AND table_name = 'profiles'
    ) THEN
        RAISE EXCEPTION 'FAILED: Table browsers.profiles does not exist!';
    END IF;

    -- Check essential C++ anti-detect columns
    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'fingerprint_seed';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: fingerprint_seed missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'screen_width';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: screen_width missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'screen_height';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: screen_height missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'device_pixel_ratio';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: device_pixel_ratio missing from browsers.profiles'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'sec_ch_ua';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: sec_ch_ua missing from browsers.profiles'; END IF;

    -- Guardrail: Ensure redundant columns are NOT present
    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'canvas_mode';
    IF FOUND THEN RAISE EXCEPTION 'FAILED: canvas_mode should NOT be in browsers.profiles (handled by C++ PRNG seed)'; END IF;

    PERFORM 1 FROM information_schema.columns WHERE table_schema = 'browsers' AND table_name = 'profiles' AND column_name = 'webgl_vendor';
    IF FOUND THEN RAISE EXCEPTION 'FAILED: webgl_vendor should NOT be in browsers.profiles (handled by C++ PRNG seed)'; END IF;

    RAISE NOTICE ' [PASS] All streamlined C++ engine columns verified on browsers.profiles (zero redundancy).';

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
    -- TEST 7: Business Functions & Backward Compatibility Views
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 7] Verifying lease functions and compatibility views...';
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
        SELECT 1 FROM pg_proc WHERE proname = 'upsert_profile' AND pronamespace = 'browsers'::regnamespace
    ) THEN
        RAISE EXCEPTION 'FAILED: Function browsers.upsert_profile does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'upsert_browser_profile' AND pronamespace = 'public'::regnamespace
    ) THEN
        RAISE EXCEPTION 'FAILED: Wrapper function public.upsert_browser_profile does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.views WHERE table_schema = 'workers' AND table_name = 'browsers'
    ) THEN
        RAISE EXCEPTION 'FAILED: Backward compatibility view workers.browsers does not exist!';
    ELSE
        RAISE NOTICE ' [PASS] Backward compatibility view workers.browsers verified.';
    END IF;

    RAISE NOTICE ' [PASS] All business logic functions and compatibility views verified.';
    RAISE NOTICE '=============================================================';
    RAISE NOTICE ' [SUCCESS] ALL 7 TESTS FOR BROWSERS PLUGIN PASSED (100%%)';
    RAISE NOTICE '=============================================================';
END $$;
