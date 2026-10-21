-- ============================================================================
-- TEST SUITE: 02D_VERIFY_OVERWRITE_AND_ADVISORY_WARNING.SQL
-- Description: Unit test suite verifying optimistic overwrite (Last-Write-Wins)
--              and advisory in-use warning for runners.acquire_browser and
--              runners.release_browser.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_tenant_id UUID;
    v_device_a_id UUID;
    v_device_b_id UUID;
    v_token_a TEXT := 'token_device_alpha_12345';
    v_token_b TEXT := 'token_device_beta_67890';
    v_browser_id UUID;
    v_res JSONB;
BEGIN
    RAISE NOTICE '>>> [TEST 1] Setting up mock tenant, devices, and browser profile...';

    -- 1. Create Mock Tenant
    INSERT INTO public.tenants (name, slug)
    VALUES ('Advisory Test Tenant', 'advisory-test-' || substr(md5(random()::text), 1, 8))
    RETURNING id INTO v_tenant_id;

    -- 2. Create Mock Device A
    INSERT INTO runners.devices (tenant_id, name, machine_fingerprint, device_token_hash, status)
    VALUES (
        v_tenant_id,
        'Device-Alpha-Workstation',
        'fp-alpha-' || substr(md5(random()::text), 1, 16),
        encode(digest(v_token_a, 'sha256'), 'hex'),
        'idle'
    )
    RETURNING id INTO v_device_a_id;

    -- 3. Create Mock Device B
    INSERT INTO runners.devices (tenant_id, name, machine_fingerprint, device_token_hash, status)
    VALUES (
        v_tenant_id,
        'Device-Beta-Laptop',
        'fp-beta-' || substr(md5(random()::text), 1, 16),
        encode(digest(v_token_b, 'sha256'), 'hex'),
        'idle'
    )
    RETURNING id INTO v_device_b_id;

    -- 4. Create Mock Browser Profile
    INSERT INTO runners.browsers (tenant_id, name, fingerprint_seed, os_platform, status)
    VALUES (v_tenant_id, 'FB-Ads-Profile-01', 123456789, 'windows', 'idle')
    RETURNING id INTO v_browser_id;

    RAISE NOTICE ' [PASS] Mock fixtures created: Tenant %, Browser %', v_tenant_id, v_browser_id;

    -- ========================================================================
    -- [TEST 2] Device A acquires browser profile
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 2] Device A acquiring browser profile...';
    v_res := runners.acquire_browser(v_browser_id, v_device_a_id, v_token_a);

    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Device A acquire failed: %', v_res;
    END IF;

    IF (v_res->>'in_use_warning')::boolean IS TRUE THEN
        RAISE EXCEPTION 'FAILED: Device A should not have received an in_use_warning!';
    END IF;

    -- Verify DB state
    IF NOT EXISTS (
        SELECT 1 FROM runners.browsers 
        WHERE id = v_browser_id AND status = 'running' AND locked_by_device_id = v_device_a_id
    ) THEN
        RAISE EXCEPTION 'FAILED: Browser state not updated for Device A!';
    END IF;

    RAISE NOTICE ' [PASS] Device A acquired browser profile successfully without warning.';

    -- ========================================================================
    -- [TEST 3] Device B opens the SAME profile while Device A is running
    --          MUST SUCCEED (no hard lock) and return in_use_warning = true
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 3] Device B acquiring already-running profile (Optimistic Overwrite)...';
    v_res := runners.acquire_browser(v_browser_id, v_device_b_id, v_token_b);

    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Device B was blocked! Hard lock is still present: %', v_res;
    END IF;

    IF (v_res->>'in_use_warning')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Device B did not receive in_use_warning!';
    END IF;

    IF (v_res->'warning_details'->>'active_device_name') <> 'Device-Alpha-Workstation' THEN
        RAISE EXCEPTION 'FAILED: Expected active device Device-Alpha-Workstation, got: %', (v_res->'warning_details'->>'active_device_name');
    END IF;

    -- Verify DB state transferred to Device B
    IF NOT EXISTS (
        SELECT 1 FROM runners.browsers 
        WHERE id = v_browser_id AND status = 'running' AND locked_by_device_id = v_device_b_id
    ) THEN
        RAISE EXCEPTION 'FAILED: Browser state not transferred to Device B!';
    END IF;

    RAISE NOTICE ' [PASS] Device B acquired profile with in_use_warning and active device name correctly.';

    -- ========================================================================
    -- [TEST 4] Device B releases profile with storage hash update
    -- ========================================================================
    RAISE NOTICE '>>> [TEST 4] Device B releasing profile and saving storage snapshot...';
    v_res := runners.release_browser(
        p_browser_id => v_browser_id,
        p_device_id => v_device_b_id,
        p_device_token => v_token_b,
        p_storage_path => v_tenant_id::text || '/' || v_browser_id::text || '.zip',
        p_storage_size_bytes => 1048576,
        p_storage_hash => 'sha256-mock-hash-beta',
        p_cookies_count => 42
    );

    IF (v_res->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: Device B release failed: %', v_res;
    END IF;

    -- Verify DB state is idle and storage metadata updated
    IF NOT EXISTS (
        SELECT 1 FROM runners.browsers 
        WHERE id = v_browser_id 
          AND status = 'idle' 
          AND locked_by_device_id IS NULL 
          AND storage_hash = 'sha256-mock-hash-beta'
          AND cookies_count = 42
    ) THEN
        RAISE EXCEPTION 'FAILED: Browser state not restored to idle or storage hash missing!';
    END IF;

    RAISE NOTICE ' [PASS] Device B released browser profile and synced storage successfully.';
END $$;

ROLLBACK;
