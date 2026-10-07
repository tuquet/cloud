-- ============================================================================
-- MIGRATION: 20261007000002_advisory_in_use_warning_and_overwrite.sql
-- Description: Transition from Hard Mutex Lease Lock to Optimistic Overwrite
--              (Last-Write-Wins) with In-Use Advisory Warning for Browser Profiles.
-- Standard: GoLogin / AdsPower Multi-Device Concurrent Usability Standard
-- ============================================================================

-- 1. UPDATE RPC runners.acquire_browser
--    Eliminate hard lock rejections. Always allow launch, but return warning
--    details when another device is currently running the profile.
CREATE OR REPLACE FUNCTION runners.acquire_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_device_name VARCHAR(128);
    v_browser RECORD;
    v_proxy RECORD;
    v_resolved_proxy TEXT := NULL;
    v_in_use_warning BOOLEAN := false;
    v_active_device_name VARCHAR(128) := NULL;
    v_active_device_id UUID := NULL;
    v_active_since TIMESTAMPTZ := NULL;
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- 1. Authenticate Device
    SELECT tenant_id, name INTO v_device_tenant_id, v_device_name
    FROM runners.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- 2. Fetch Browser Profile with Row Lock
    SELECT * INTO v_browser
    FROM runners.browsers
    WHERE id = p_browser_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_browser.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Browser profile not found in tenant');
    END IF;

    -- 3. In-Use Advisory Detection: Check if active on another device without blocking
    IF v_browser.status = 'running' AND v_browser.locked_by_device_id IS NOT NULL AND v_browser.locked_by_device_id <> p_device_id THEN
        v_in_use_warning := true;
        v_active_device_id := v_browser.locked_by_device_id;
        v_active_since := v_browser.locked_at;

        -- Retrieve human-readable active device name
        SELECT name INTO v_active_device_name
        FROM runners.devices
        WHERE id = v_active_device_id;

        IF v_active_device_name IS NULL THEN
            v_active_device_name := 'Another Device';
        END IF;
    END IF;

    -- 4. Resolve Proxy Configuration
    IF v_browser.proxy_id IS NOT NULL THEN
        SELECT * INTO v_proxy FROM runners.proxies WHERE id = v_browser.proxy_id AND tenant_id = v_device_tenant_id;
        IF v_proxy.id IS NOT NULL THEN
            IF v_proxy.username IS NOT NULL AND v_proxy.username <> '' THEN
                v_resolved_proxy := format('%s://%s:%s@%s:%s', v_proxy.protocol, v_proxy.username, COALESCE(v_proxy.password_hash, ''), v_proxy.host, v_proxy.port);
            ELSE
                v_resolved_proxy := format('%s://%s:%s', v_proxy.protocol, v_proxy.host, v_proxy.port);
            END IF;
        END IF;
    ELSIF v_browser.custom_proxy IS NOT NULL AND v_browser.custom_proxy <> '' THEN
        v_resolved_proxy := v_browser.custom_proxy;
    END IF;

    -- 5. Optimistic Overwrite: Transfer active session tracking to requesting device
    UPDATE runners.browsers
    SET 
        status = 'running',
        locked_by_device_id = p_device_id,
        locked_at = timezone('utc'::text, now()),
        last_launched_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = p_browser_id;

    RETURN jsonb_build_object(
        'success', true,
        'in_use_warning', v_in_use_warning,
        'warning_details', CASE 
            WHEN v_in_use_warning THEN jsonb_build_object(
                'message', format('Profile is currently active on device "%s"', v_active_device_name),
                'active_device_id', v_active_device_id,
                'active_device_name', v_active_device_name,
                'active_since', v_active_since
            )
            ELSE NULL 
        END,
        'browser', jsonb_build_object(
            'id', v_browser.id,
            'name', v_browser.name,
            'browser_type', v_browser.browser_type,
            'engine_version', v_browser.engine_version,
            'fingerprint_seed', v_browser.fingerprint_seed,
            'os_platform', v_browser.os_platform,
            'os_version', v_browser.os_version,
            'browser_brand', v_browser.browser_brand,
            'cpu_cores', v_browser.cpu_cores,
            'ram_gb', v_browser.ram_gb,
            'timezone', v_browser.timezone,
            'locale', v_browser.locale,
            'accept_languages', v_browser.accept_languages,
            'webrtc_mode', v_browser.webrtc_mode,
            'proxy', v_resolved_proxy,
            'storage_path', v_browser.storage_path,
            'storage_size_bytes', v_browser.storage_size_bytes,
            'storage_hash', v_browser.storage_hash,
            'cookies_count', v_browser.cookies_count,
            'last_synced_at', v_browser.last_synced_at
        ),
        'device_name', v_device_name,
        'launched_at', timezone('utc'::text, now())
    );
END;
$$;

-- 2. UPDATE RPC runners.release_browser
--    Last-Write-Wins: Always accept storage snapshot updates and transition back to idle.
CREATE OR REPLACE FUNCTION runners.release_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT NULL,
    p_storage_hash TEXT DEFAULT NULL,
    p_cookies_count INT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_browser RECORD;
    v_overwritten BOOLEAN := false;
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- 1. Authenticate Device
    SELECT tenant_id INTO v_device_tenant_id
    FROM runners.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- 2. Fetch Browser Profile with Row Lock
    SELECT * INTO v_browser
    FROM runners.browsers
    WHERE id = p_browser_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_browser.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Browser profile not found');
    END IF;

    -- 3. Note if another device was concurrently active
    IF v_browser.locked_by_device_id IS NOT NULL AND v_browser.locked_by_device_id <> p_device_id THEN
        v_overwritten := true;
    END IF;

    -- 4. Last-Write-Wins: Always persist latest session storage snapshot and reset status to idle
    UPDATE runners.browsers
    SET 
        status = 'idle',
        locked_by_device_id = NULL,
        locked_at = NULL,
        storage_path = COALESCE(p_storage_path, v_browser.storage_path),
        storage_size_bytes = COALESCE(p_storage_size_bytes, v_browser.storage_size_bytes),
        storage_hash = COALESCE(p_storage_hash, v_browser.storage_hash),
        cookies_count = COALESCE(p_cookies_count, v_browser.cookies_count),
        last_synced_at = CASE WHEN p_storage_path IS NOT NULL THEN timezone('utc'::text, now()) ELSE v_browser.last_synced_at END,
        metadata = v_browser.metadata || p_metadata,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_browser_id;

    RETURN jsonb_build_object(
        'success', true,
        'browser_id', p_browser_id,
        'status', 'idle',
        'overwritten_concurrently', v_overwritten,
        'released_at', timezone('utc'::text, now())
    );
END;
$$;

GRANT EXECUTE ON FUNCTION runners.acquire_browser(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION runners.release_browser(UUID, UUID, TEXT, TEXT, BIGINT, TEXT, INT, JSONB) TO authenticated, service_role;

-- 3. Public PostgREST Facades (Required for /rest/v1/rpc/)
CREATE OR REPLACE FUNCTION public.acquire_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.acquire_browser(p_browser_id, p_device_id, p_device_token);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT NULL,
    p_storage_hash TEXT DEFAULT NULL,
    p_cookies_count INT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.release_browser(
        p_browser_id, p_device_id, p_device_token,
        p_storage_path, p_storage_size_bytes, p_storage_hash,
        p_cookies_count, p_metadata
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.acquire_browser(UUID, UUID, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.release_browser(UUID, UUID, TEXT, TEXT, BIGINT, TEXT, INT, JSONB) TO authenticated, anon, service_role;

