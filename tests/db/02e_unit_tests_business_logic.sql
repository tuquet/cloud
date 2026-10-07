-- ============================================================================
-- TEST SUITE: 02E_UNIT_TESTS_BUSINESS_LOGIC.SQL
-- Description: Comprehensive granular unit tests for core business logic:
--              1. Device Enrollment & Idempotent Token Reissue
--              2. Token Hash Authentication & Invalid Token Rejection
--              3. Clean Browser Profile Acquisition & Fingerprint Integrity
--              4. Cross-Tenant Multi-Tenant Isolation
--              5. Non-Existent Profile Handling
--              6. Advisory In-Use Warning (Multi-Device GoLogin Standard)
--              7. Last-Write-Wins Overwrite & Concurrent Overwrite Detection
--              8. Heartbeat & Telemetry Tracking
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_tenant_a_id UUID;
    v_tenant_b_id UUID;
    v_dev_a_res JSONB;
    v_dev_a_id UUID;
    v_dev_a_token TEXT;
    v_dev_a_reissue JSONB;
    v_dev_b_res JSONB;
    v_dev_b_id UUID;
    v_dev_b_token TEXT;
    v_browser_a_id UUID;
    v_browser_b_id UUID;
    v_res JSONB;
    v_hb_res JSONB;
BEGIN
    RAISE NOTICE '============================================================';
    RAISE NOTICE '>>> STARTING BUSINESS LOGIC UNIT TESTS';
    RAISE NOTICE '============================================================';

    -- ------------------------------------------------------------------------
    -- FIXTURE SETUP: Create 2 Isolated Tenants
    -- ------------------------------------------------------------------------
    INSERT INTO public.tenants (name, slug)
    VALUES ('Acme Business Tenant A', 'acme-biz-a-' || substr(md5(random()::text), 1, 8))
    RETURNING id INTO v_tenant_a_id;

    INSERT INTO public.tenants (name, slug)
    VALUES ('Beta Foreign Tenant B', 'beta-foreign-b-' || substr(md5(random()::text), 1, 8))
    RETURNING id INTO v_tenant_b_id;

    RAISE NOTICE '[SETUP] Created Tenants: Tenant A %, Tenant B %', v_tenant_a_id, v_tenant_b_id;

    -- ========================================================================
    -- UNIT TEST 1: Device Enrollment & Identity
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 1] Device Enrollment: Fresh device registration';
    v_dev_a_res := runners.enroll_device(
        p_machine_fingerprint => 'HWID-TEST-ALPHA-001',
        p_name => 'Workstation-Alpha',
        p_os_info => 'Linux x86_64',
        p_cpu_cores => 8,
        p_ram_mb => 16384,
        p_capabilities => '["browser:automa", "stealth:cdp"]'::jsonb,
        p_metadata => '{"env": "test"}'::jsonb,
        p_tenant_id => v_tenant_a_id
    );

    IF (v_dev_a_res->>'device_id') IS NULL OR (v_dev_a_res->>'device_token') IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Device enrollment did not return device_id or device_token: %', v_dev_a_res;
    END IF;

    v_dev_a_id := (v_dev_a_res->>'device_id')::UUID;
    v_dev_a_token := v_dev_a_res->>'device_token';
    RAISE NOTICE ' [PASS] Device A enrolled: ID %, Token prefix %', v_dev_a_id, substr(v_dev_a_token, 1, 12);

    -- ========================================================================
    -- UNIT TEST 2: Device Re-enrollment Idempotency
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 2] Device Enrollment Idempotency: Re-enrolling same fingerprint';
    v_dev_a_reissue := runners.enroll_device(
        p_machine_fingerprint => 'HWID-TEST-ALPHA-001',
        p_name => 'Workstation-Alpha-Updated',
        p_os_info => 'Linux x86_64 Updated',
        p_cpu_cores => 16,
        p_ram_mb => 32768,
        p_capabilities => '["browser:automa"]'::jsonb,
        p_metadata => '{"env": "test-updated"}'::jsonb,
        p_tenant_id => v_tenant_a_id
    );

    IF (v_dev_a_reissue->>'device_id')::UUID <> v_dev_a_id THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Re-enrolled device ID changed! Expected %, got %', v_dev_a_id, v_dev_a_reissue->>'device_id';
    END IF;

    -- Update active token to the reissued one
    v_dev_a_token := v_dev_a_reissue->>'device_token';
    RAISE NOTICE ' [PASS] Idempotent re-enrollment preserved device ID % and refreshed token.', v_dev_a_id;

    -- Enroll Device B for Tenant A
    v_dev_b_res := runners.enroll_device(
        p_machine_fingerprint => 'HWID-TEST-BETA-002',
        p_name => 'Workstation-Beta',
        p_os_info => 'Windows 11 x64',
        p_cpu_cores => 4,
        p_ram_mb => 8192,
        p_capabilities => '["browser:automa"]'::jsonb,
        p_metadata => '{}'::jsonb,
        p_tenant_id => v_tenant_a_id
    );
    v_dev_b_id := (v_dev_b_res->>'device_id')::UUID;
    v_dev_b_token := v_dev_b_res->>'device_token';

    -- Create Browser Profiles
    INSERT INTO runners.browsers (
        tenant_id, name, browser_type, engine_version, fingerprint_seed,
        os_platform, os_version, browser_brand, cpu_cores, ram_gb,
        timezone, locale, accept_languages, status
    ) VALUES (
        v_tenant_a_id, 'FB-Campaign-Profile-01', 'chromium', '148.0.7778.215', 133742,
        'windows', '10.0.0', 'Chrome', 8, 16,
        'Asia/Ho_Chi_Minh', 'vi-VN', 'vi-VN,vi,en-US,en', 'idle'
    ) RETURNING id INTO v_browser_a_id;

    INSERT INTO runners.browsers (
        tenant_id, name, browser_type, status
    ) VALUES (
        v_tenant_b_id, 'Foreign-Tenant-Profile', 'chromium', 'idle'
    ) RETURNING id INTO v_browser_b_id;

    -- ========================================================================
    -- UNIT TEST 3: Authentication & Invalid Token Rejection
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 3] Authentication: Reject invalid device token';
    v_res := runners.acquire_browser(v_browser_a_id, v_dev_a_id, 'invalid_fake_token_hex_123');
    IF (v_res->>'success')::boolean IS NOT FALSE OR (v_res->>'error') <> 'Invalid device credentials' THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Invalid token was not rejected: %', v_res;
    END IF;
    RAISE NOTICE ' [PASS] Invalid device credentials rejected properly.';

    -- ========================================================================
    -- UNIT TEST 4: Clean Browser Acquisition & Fingerprint Integrity
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 4] Browser Acquisition: Clean single-device acquire';
    v_res := runners.acquire_browser(v_browser_a_id, v_dev_a_id, v_dev_a_token);
    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Clean acquire failed: %', v_res;
    END IF;

    IF (v_res->>'in_use_warning')::boolean IS TRUE THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Should not return in_use_warning on idle profile!';
    END IF;

    IF (v_res->'browser'->>'fingerprint_seed')::int <> 133742 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Fingerprint seed corrupted: %', v_res->'browser'->>'fingerprint_seed';
    END IF;

    IF (v_res->'browser'->>'os_platform') <> 'windows' OR (v_res->'browser'->>'timezone') <> 'Asia/Ho_Chi_Minh' THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Hardware emulation attributes missing or incorrect: %', v_res->'browser';
    END IF;
    RAISE NOTICE ' [PASS] Clean acquire succeeded with full fingerprint spec.';

    -- ========================================================================
    -- UNIT TEST 5: Multi-Tenant Boundary Isolation
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 5] Multi-Tenant Isolation: Device A cannot access Tenant B profile';
    v_res := runners.acquire_browser(v_browser_b_id, v_dev_a_id, v_dev_a_token);
    IF (v_res->>'success')::boolean IS NOT FALSE OR (v_res->>'error') <> 'Browser profile not found in tenant' THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Cross-tenant isolation breach! Result: %', v_res;
    END IF;
    RAISE NOTICE ' [PASS] Cross-tenant profile access strictly denied.';

    -- ========================================================================
    -- UNIT TEST 6: Non-Existent Profile Handling
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 6] Non-Existent Profile: Graceful error response';
    v_res := runners.acquire_browser('00000000-0000-0000-0000-000000000000'::UUID, v_dev_a_id, v_dev_a_token);
    IF (v_res->>'success')::boolean IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Non-existent profile returned success: %', v_res;
    END IF;
    RAISE NOTICE ' [PASS] Non-existent profile handled gracefully.';

    -- ========================================================================
    -- UNIT TEST 7: Advisory In-Use Warning (GoLogin Multi-Device Standard)
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 7] Advisory In-Use Warning: Device B acquires profile active on Device A';
    v_res := runners.acquire_browser(v_browser_a_id, v_dev_b_id, v_dev_b_token);
    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Device B was blocked! Hard lock must NOT be present: %', v_res;
    END IF;

    IF (v_res->>'in_use_warning')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Device B did not receive in_use_warning: true';
    END IF;

    IF (v_res->'warning_details'->>'active_device_name') <> 'Workstation-Alpha-Updated' THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Expected active device Workstation-Alpha-Updated, got %', v_res->'warning_details';
    END IF;
    RAISE NOTICE ' [PASS] Advisory In-Use Warning verified: success=true, in_use_warning=true, active_device_name=Workstation-Alpha-Updated.';

    -- ========================================================================
    -- UNIT TEST 8: Last-Write-Wins Overwrite & Concurrent Overwrite Detection
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 8] Last-Write-Wins Overwrite: Device A releases while Device B holds lock';
    v_res := runners.release_browser(
        p_browser_id => v_browser_a_id,
        p_device_id => v_dev_a_id,
        p_device_token => v_dev_a_token,
        p_storage_path => 'profiles/' || v_browser_a_id::text || '/dev_a.tar.zst',
        p_storage_size_bytes => 1048576,
        p_storage_hash => '7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069',
        p_cookies_count => 25,
        p_metadata => '{"last_worker": "alpha"}'::jsonb
    );

    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Device A release failed: %', v_res;
    END IF;

    IF (v_res->>'overwritten_concurrently')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Expected overwritten_concurrently=true for Device A release!';
    END IF;
    RAISE NOTICE ' [PASS] Device A release detected concurrent overwrite: overwritten_concurrently=true.';

    -- Device B releases afterwards
    v_res := runners.release_browser(
        p_browser_id => v_browser_a_id,
        p_device_id => v_dev_b_id,
        p_device_token => v_dev_b_token,
        p_storage_path => 'profiles/' || v_browser_a_id::text || '/dev_b.tar.zst',
        p_storage_size_bytes => 2097152,
        p_storage_hash => 'a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef',
        p_cookies_count => 50,
        p_metadata => '{"last_worker": "beta"}'::jsonb
    );

    IF (v_res->>'success')::boolean IS NOT TRUE OR (v_res->>'status') <> 'idle' THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Device B release failed or not idle: %', v_res;
    END IF;

    -- Verify final DB state has Device B's snapshot (Last-Write-Wins)
    IF NOT EXISTS (
        SELECT 1 FROM runners.browsers
        WHERE id = v_browser_a_id
          AND status = 'idle'
          AND locked_by_device_id IS NULL
          AND storage_path = 'profiles/' || v_browser_a_id::text || '/dev_b.tar.zst'
          AND storage_size_bytes = 2097152
          AND cookies_count = 50
    ) THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Final database state does not match Device B snapshot!';
    END IF;
    RAISE NOTICE ' [PASS] Device B release persisted final snapshot cleanly. Status=idle.';

    -- ========================================================================
    -- UNIT TEST 9: Heartbeat & Telemetry Tracking
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 9] Heartbeat: Updating device liveness and active jobs';
    v_hb_res := runners.heartbeat(
        p_device_id => v_dev_a_id,
        p_device_token => v_dev_a_token,
        p_active_jobs => 2,
        p_telemetry => '{"cpu_pct": 14.5, "ram_used_mb": 4096}'::jsonb
    );

    IF (v_hb_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Heartbeat failed: %', v_hb_res;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM runners.devices
        WHERE id = v_dev_a_id
          AND (telemetry->>'cpu_pct')::numeric = 14.5
    ) THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Device telemetry was not saved in DB!';
    END IF;
    RAISE NOTICE ' [PASS] Heartbeat and telemetry recorded accurately.';

    RAISE NOTICE '============================================================';
    RAISE NOTICE '🎉 ALL 9 DATABASE BUSINESS LOGIC UNIT TESTS PASSED!';
    RAISE NOTICE '============================================================';
END $$;

ROLLBACK;
