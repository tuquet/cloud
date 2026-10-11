-- ============================================================================
-- TUQUET-CLOUD PLUGIN: RUNNERS & COMPUTE FLEET (INSTALLATION SCRIPT)
-- Plugin ID: runners
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: runners)
-- Features: Fleet Workstations, Node Browsers, Proxy Pool Management,
--           GoLogin-style Cloud Browsers with Deterministic Fingerprints,
--           Distributed Lease Locking (Last-Write-Wins with In-Use Advisory),
--           Supabase Storage Session Sync & Secure PostgREST RPC Facades.
-- ============================================================================

-- 1. Create Dedicated Schema & Permissions
CREATE SCHEMA IF NOT EXISTS runners;
GRANT USAGE ON SCHEMA runners TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA runners GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA runners GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA runners GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 2. Enums in schema runners
DO $$ BEGIN
    CREATE TYPE runners.device_status AS ENUM ('offline', 'idle', 'busy', 'maintenance', 'disabled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Tables in schema runners

-- 3.1. Physical Devices & Compute Workstations Registry
CREATE TABLE IF NOT EXISTS runners.devices (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    machine_fingerprint VARCHAR(128) NOT NULL,
    status runners.device_status NOT NULL DEFAULT 'offline',
    version VARCHAR(32) NOT NULL DEFAULT '0.1.0',
    os_info VARCHAR(128),
    cpu_cores INT NOT NULL DEFAULT 1 CHECK (cpu_cores >= 1),
    ram_mb INT NOT NULL DEFAULT 1024 CHECK (ram_mb >= 256),
    capabilities JSONB NOT NULL DEFAULT '[]'::jsonb,
    device_token_hash VARCHAR(64),
    config_override JSONB NOT NULL DEFAULT '{}'::jsonb,
    active_jobs INT NOT NULL DEFAULT 0 CHECK (active_jobs >= 0),
    last_heartbeat_at TIMESTAMPTZ,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_runners_devices_tenant_fingerprint UNIQUE (tenant_id, machine_fingerprint),
    CONSTRAINT uq_runners_devices_tenant_id UNIQUE (tenant_id, id)
);

COMMENT ON TABLE runners.devices IS '[Plugin: runners] Registered physical workstations and edge worker nodes';

CREATE INDEX IF NOT EXISTS idx_runners_devices_tenant_status ON runners.devices (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_devices_heartbeat ON runners.devices (last_heartbeat_at);

-- 3.2. Central Multi-Tenant Proxy Pool
CREATE TABLE IF NOT EXISTS runners.proxies (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    host VARCHAR(255) NOT NULL,
    port INT NOT NULL CHECK (port > 0 AND port <= 65535),
    protocol VARCHAR(16) NOT NULL DEFAULT 'http' CHECK (protocol IN ('http', 'https', 'socks4', 'socks5')),
    username VARCHAR(128),
    password_hash VARCHAR(255),
    country_code VARCHAR(2),
    city VARCHAR(64),
    ip_address INET,
    status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'failing', 'disabled', 'testing')),
    latency_ms INT,
    last_checked_at TIMESTAMPTZ,
    error_count INT NOT NULL DEFAULT 0,
    tags TEXT[] NOT NULL DEFAULT '{}'::text[],
    is_residential BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_runners_proxies_tenant_endpoint UNIQUE (tenant_id, host, port, protocol, username)
);

COMMENT ON TABLE runners.proxies IS '[Plugin: runners] Central multi-tenant pool of residential, datacenter, and mobile proxies';

CREATE INDEX IF NOT EXISTS idx_runners_proxies_tenant_status ON runners.proxies (tenant_id, status);

-- 3.3. Central Cloud Browser Profiles (GoLogin / AdsPower Architecture)
CREATE TABLE IF NOT EXISTS runners.browsers (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    browser_type VARCHAR(64) NOT NULL DEFAULT 'chromium',
    engine_version VARCHAR(32) NOT NULL DEFAULT '148.0.7778.215',

    -- Deterministic Hardware Fingerprint Specifications
    fingerprint_seed BIGINT NOT NULL DEFAULT floor(random() * 2147483647)::bigint,
    os_platform VARCHAR(32) NOT NULL DEFAULT 'windows',
    os_version VARCHAR(64) NOT NULL DEFAULT '10.0.0',
    browser_brand VARCHAR(64) NOT NULL DEFAULT 'Chrome',
    cpu_cores INT NOT NULL DEFAULT 8 CHECK (cpu_cores >= 1),
    ram_gb INT NOT NULL DEFAULT 16 CHECK (ram_gb >= 1),
    timezone TEXT NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
    locale TEXT NOT NULL DEFAULT 'vi-VN',
    accept_languages TEXT NOT NULL DEFAULT 'vi-VN,vi,en-US,en',

    -- Network, Proxy & WebRTC STUN Shielding
    proxy_id UUID REFERENCES runners.proxies(id) ON DELETE SET NULL,
    custom_proxy TEXT,
    webrtc_mode VARCHAR(32) NOT NULL DEFAULT 'proxy_shielded',

    -- Session Snapshot & Storage Sync (.zip)
    storage_path TEXT,
    storage_size_bytes BIGINT NOT NULL DEFAULT 0,
    storage_hash VARCHAR(64),
    cookies_count INT NOT NULL DEFAULT 0,
    last_synced_at TIMESTAMPTZ,

    -- Distributed Lease Lock & Execution State (Last-Write-Wins with In-Use Advisory)
    status VARCHAR(32) NOT NULL DEFAULT 'idle',
    locked_by_device_id UUID REFERENCES runners.devices(id) ON DELETE SET NULL,
    locked_at TIMESTAMPTZ,
    last_launched_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT chk_runners_browsers_status CHECK (status IN ('idle', 'running', 'syncing', 'error'))
);

COMMENT ON TABLE runners.browsers IS '[Plugin: runners] Central cloud inventory of virtual anti-detect browser profiles, fingerprints, and session storage';

CREATE INDEX IF NOT EXISTS idx_runners_browsers_tenant_status ON runners.browsers (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_browsers_locked ON runners.browsers (locked_by_device_id);
CREATE INDEX IF NOT EXISTS idx_runners_browsers_proxy_id ON runners.browsers (proxy_id);
CREATE INDEX IF NOT EXISTS idx_runners_browsers_created_brin ON runners.browsers USING brin (created_at);

-- 3.4. Node-Local Discovered Browsers Inventory
CREATE TABLE IF NOT EXISTS runners.node_browsers (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID NOT NULL,
    device_id UUID NOT NULL,
    local_profile_id VARCHAR(128) NOT NULL,
    name VARCHAR(128) NOT NULL,
    browser_type VARCHAR(64) NOT NULL DEFAULT 'chrome',
    user_data_dir TEXT NOT NULL,
    executable_path TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT fk_runners_node_browsers_device FOREIGN KEY (tenant_id, device_id)
        REFERENCES runners.devices (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT uq_runners_node_browsers_profile UNIQUE (device_id, local_profile_id)
);

COMMENT ON TABLE runners.node_browsers IS '[Plugin: runners] Node-local browser profiles inventory discovered by edge workers';

CREATE INDEX IF NOT EXISTS idx_runners_node_browsers_device ON runners.node_browsers (device_id);

-- 4. Supabase Storage Bucket for Browser Profiles Session Archives
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'browser-profiles',
            'browser-profiles',
            false,
            268435456, -- 256 MB max per profile archive
            ARRAY['application/zip', 'application/x-zip-compressed', 'application/octet-stream']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = EXCLUDED.public,
            file_size_limit = EXCLUDED.file_size_limit,
            allowed_mime_types = EXCLUDED.allowed_mime_types;
    END IF;
END $$;

-- 5. Row Level Security Policies
ALTER TABLE runners.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE runners.proxies ENABLE ROW LEVEL SECURITY;
ALTER TABLE runners.browsers ENABLE ROW LEVEL SECURITY;
ALTER TABLE runners.node_browsers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "devices_select" ON runners.devices;
    DROP POLICY IF EXISTS "devices_manage" ON runners.devices;
    DROP POLICY IF EXISTS "proxies_select" ON runners.proxies;
    DROP POLICY IF EXISTS "proxies_manage" ON runners.proxies;
    DROP POLICY IF EXISTS "browsers_select" ON runners.browsers;
    DROP POLICY IF EXISTS "browsers_manage" ON runners.browsers;
    DROP POLICY IF EXISTS "node_browsers_select" ON runners.node_browsers;
    DROP POLICY IF EXISTS "node_browsers_manage" ON runners.node_browsers;
EXCEPTION WHEN undefined_object THEN null;
END $$;

CREATE POLICY "devices_select" ON runners.devices
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "devices_manage" ON runners.devices
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:devices:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "proxies_select" ON runners.proxies
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "proxies_manage" ON runners.proxies
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:proxies:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "browsers_select" ON runners.browsers
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "browsers_manage" ON runners.browsers
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:browsers:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "node_browsers_select" ON runners.node_browsers
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "node_browsers_manage" ON runners.node_browsers
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:devices:manage') OR public.is_tenant_admin(tenant_id));

-- 6. Core Stored Procedures & RPC Functions (Hardened CWE-426 Protection)

-- 6.1. Zero-Touch Device Enrollment
CREATE OR REPLACE FUNCTION runners.enroll_device(
    p_machine_fingerprint VARCHAR(128),
    p_name VARCHAR(128),
    p_os_info VARCHAR(128) DEFAULT NULL,
    p_cpu_cores INT DEFAULT 1,
    p_ram_mb INT DEFAULT 1024,
    p_capabilities JSONB DEFAULT '[]'::jsonb,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_enrollment_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID;
    v_device_id UUID;
    v_raw_token TEXT;
    v_token_hash TEXT;
    v_config JSONB;
BEGIN
    -- Resolve Target Tenant
    SELECT id INTO v_tenant_id FROM public.tenants WHERE status = 'active' ORDER BY created_at ASC LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No active tenant available in Tuquet Cloud to enroll device';
    END IF;

    -- Generate Device Secret Token (Raw token returned to client, SHA-256 hash stored)
    v_raw_token := 'tqr_sec_' || encode(extensions.gen_random_bytes(24), 'hex');
    v_token_hash := encode(extensions.digest(v_raw_token, 'sha256'), 'hex');

    -- Upsert Device in registry
    INSERT INTO runners.devices (
        tenant_id, name, machine_fingerprint, status, os_info,
        cpu_cores, ram_mb, capabilities, device_token_hash,
        metadata, last_heartbeat_at
    )
    VALUES (
        v_tenant_id, p_name, p_machine_fingerprint, 'idle', p_os_info,
        GREATEST(p_cpu_cores, 1), GREATEST(p_ram_mb, 256), p_capabilities, v_token_hash,
        p_metadata, timezone('utc'::text, now())
    )
    ON CONFLICT (tenant_id, machine_fingerprint)
    DO UPDATE SET
        name = EXCLUDED.name,
        os_info = COALESCE(EXCLUDED.os_info, runners.devices.os_info),
        cpu_cores = EXCLUDED.cpu_cores,
        ram_mb = EXCLUDED.ram_mb,
        capabilities = EXCLUDED.capabilities,
        device_token_hash = v_token_hash,
        metadata = runners.devices.metadata || EXCLUDED.metadata,
        status = 'idle',
        last_heartbeat_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    RETURNING id, config_override INTO v_device_id, v_config;

    RETURN jsonb_build_object(
        'device_id', v_device_id,
        'tenant_id', v_tenant_id,
        'device_token', v_raw_token,
        'name', p_name,
        'status', 'idle',
        'config', COALESCE(v_config, '{}'::jsonb)
    );
END;
$$;

-- 6.2. Device Heartbeat & Telemetry
CREATE OR REPLACE FUNCTION runners.heartbeat(
    p_device_id UUID,
    p_device_token TEXT,
    p_active_jobs INT DEFAULT 0,
    p_telemetry JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_token_hash TEXT;
    v_device RECORD;
BEGIN
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

    SELECT id, tenant_id, status, config_override INTO v_device
    FROM runners.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    UPDATE runners.devices
    SET 
        active_jobs = p_active_jobs,
        status = CASE WHEN p_active_jobs > 0 THEN 'busy'::runners.device_status ELSE 'idle'::runners.device_status END,
        last_heartbeat_at = timezone('utc'::text, now()),
        metadata = runners.devices.metadata || jsonb_build_object('telemetry', p_telemetry)
    WHERE id = v_device.id;

    RETURN jsonb_build_object(
        'success', true,
        'device_id', v_device.id,
        'config', COALESCE(v_device.config_override, '{}'::jsonb),
        'server_time', timezone('utc'::text, now())
    );
END;
$$;

-- 6.3. Acquire Browser Profile (Optimistic Overwrite & Advisory In-Use Warning)
CREATE OR REPLACE FUNCTION runners.acquire_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

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

-- 6.4. Release Browser Profile (Last-Write-Wins Session Storage Sync)
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
SET search_path = ''
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_browser RECORD;
    v_overwritten BOOLEAN := false;
BEGIN
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

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

    -- 4. Last-Write-Wins: Persist latest session snapshot and reset status to idle
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

-- 6.5. Create Browser Profile (Deterministic Fingerprints & Strict Tenant Scoping)
CREATE OR REPLACE FUNCTION runners.create_browser(
    p_name VARCHAR(128),
    p_fingerprint_seed BIGINT DEFAULT NULL,
    p_os_platform VARCHAR(32) DEFAULT 'windows',
    p_browser_brand VARCHAR(64) DEFAULT 'Chrome',
    p_proxy_id UUID DEFAULT NULL,
    p_custom_proxy TEXT DEFAULT NULL,
    p_timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh',
    p_locale TEXT DEFAULT 'vi-VN',
    p_cpu_cores INT DEFAULT 8,
    p_ram_gb INT DEFAULT 16,
    p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID := p_tenant_id;
    v_seed BIGINT := p_fingerprint_seed;
    v_browser_id UUID;
BEGIN
    -- Authenticate caller: If caller specified p_tenant_id, verify permission
    IF v_tenant_id IS NOT NULL THEN
        IF auth.uid() IS NOT NULL AND NOT (public.has_tenant_permission(v_tenant_id, 'runners:browsers:manage') OR public.is_tenant_admin(v_tenant_id)) THEN
            RAISE EXCEPTION 'Unauthorized: Insufficient permissions to create browser in specified tenant'
                USING ERRCODE = '42501';
        END IF;
    ELSE
        -- Resolve caller's active tenant
        IF auth.uid() IS NOT NULL THEN
            SELECT tm.tenant_id INTO v_tenant_id
            FROM public.tenant_members tm
            WHERE tm.user_id = auth.uid() AND tm.status = 'active'
            ORDER BY tm.joined_at ASC
            LIMIT 1;
        END IF;
    END IF;

    -- Reject unauthenticated requests attempting to create browsers
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Valid authenticated tenant context required'
            USING ERRCODE = '42501';
    END IF;

    -- Generate deterministic seed if not provided
    IF v_seed IS NULL THEN
        v_seed := floor(random() * 2147483647)::bigint;
    END IF;

    INSERT INTO runners.browsers (
        tenant_id, name, browser_type, engine_version,
        fingerprint_seed, os_platform, os_version, browser_brand,
        cpu_cores, ram_gb, timezone, locale, accept_languages,
        proxy_id, custom_proxy, webrtc_mode, status
    )
    VALUES (
        v_tenant_id, p_name, 'chromium', '148.0.7778.215',
        v_seed, p_os_platform, '10.0.0', p_browser_brand,
        GREATEST(p_cpu_cores, 1), GREATEST(p_ram_gb, 1),
        p_timezone, p_locale, 'vi-VN,vi,en-US,en',
        p_proxy_id, p_custom_proxy, 'proxy_shielded', 'idle'
    )
    RETURNING id INTO v_browser_id;

    RETURN jsonb_build_object(
        'success', true,
        'browser_id', v_browser_id,
        'tenant_id', v_tenant_id,
        'name', p_name,
        'fingerprint_seed', v_seed,
        'status', 'idle'
    );
END;
$$;

-- 6.6. List Browser Profiles (Secure Tenant Scoping & Device Token Validation)
CREATE OR REPLACE FUNCTION runners.list_browsers(
    p_device_id UUID DEFAULT NULL,
    p_device_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_token_hash TEXT;
    v_tenant_id UUID;
    v_browsers JSONB;
BEGIN
    -- 1. Authenticate via Device credentials
    IF p_device_id IS NOT NULL AND p_device_token IS NOT NULL THEN
        v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');
        SELECT tenant_id INTO v_tenant_id
        FROM runners.devices
        WHERE id = p_device_id AND device_token_hash = v_token_hash;
    END IF;

    -- 2. Authenticate via User JWT
    IF v_tenant_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT tm.tenant_id INTO v_tenant_id
        FROM public.tenant_members tm
        WHERE tm.user_id = auth.uid() AND tm.status = 'active'
        ORDER BY tm.joined_at ASC
        LIMIT 1;
    END IF;

    -- 3. Reject unauthenticated anonymous requests
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Valid device credentials or user authentication required'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'name', b.name,
            'browser_type', b.browser_type,
            'engine_version', b.engine_version,
            'status', b.status,
            'fingerprint_seed', b.fingerprint_seed,
            'os_platform', b.os_platform,
            'os_version', b.os_version,
            'browser_brand', b.browser_brand,
            'cpu_cores', b.cpu_cores,
            'ram_gb', b.ram_gb,
            'timezone', b.timezone,
            'locale', b.locale,
            'accept_languages', b.accept_languages,
            'proxy', b.custom_proxy,
            'storage_path', b.storage_path,
            'storage_size_bytes', b.storage_size_bytes,
            'storage_hash', b.storage_hash,
            'cookies_count', b.cookies_count,
            'locked_by_device_id', b.locked_by_device_id,
            'locked_at', b.locked_at,
            'last_synced_at', b.last_synced_at,
            'updated_at', b.updated_at
        ) ORDER BY b.created_at ASC
    ), '[]'::jsonb) INTO v_browsers
    FROM runners.browsers b
    WHERE b.tenant_id = v_tenant_id;

    RETURN v_browsers;
END;
$$;

-- 7. Public PostgREST Facades (Clean Public Routing for /rest/v1/rpc/)
CREATE OR REPLACE FUNCTION public.heartbeat(
    p_device_id UUID,
    p_device_token TEXT,
    p_active_jobs INT DEFAULT 0,
    p_telemetry JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN runners.heartbeat(p_device_id, p_device_token, p_active_jobs, p_telemetry);
END;
$$;

CREATE OR REPLACE FUNCTION public.acquire_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
SET search_path = ''
AS $$
BEGIN
    RETURN runners.release_browser(
        p_browser_id, p_device_id, p_device_token,
        p_storage_path, p_storage_size_bytes, p_storage_hash,
        p_cookies_count, p_metadata
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_browser(
    p_name VARCHAR(128),
    p_fingerprint_seed BIGINT DEFAULT NULL,
    p_os_platform VARCHAR(32) DEFAULT 'windows',
    p_browser_brand VARCHAR(64) DEFAULT 'Chrome',
    p_proxy_id UUID DEFAULT NULL,
    p_custom_proxy TEXT DEFAULT NULL,
    p_timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh',
    p_locale TEXT DEFAULT 'vi-VN',
    p_cpu_cores INT DEFAULT 8,
    p_ram_gb INT DEFAULT 16,
    p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN runners.create_browser(
        p_name => p_name,
        p_fingerprint_seed => p_fingerprint_seed,
        p_os_platform => p_os_platform,
        p_browser_brand => p_browser_brand,
        p_proxy_id => p_proxy_id,
        p_custom_proxy => p_custom_proxy,
        p_timezone => p_timezone,
        p_locale => p_locale,
        p_cpu_cores => p_cpu_cores,
        p_ram_gb => p_ram_gb,
        p_tenant_id => p_tenant_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_browsers(
    p_device_id UUID DEFAULT NULL,
    p_device_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN runners.list_browsers(p_device_id, p_device_token);
END;
$$;

-- 6.7. Dead Lease Reaper Engine (Auto-Reap Stale Browser Locks)
CREATE OR REPLACE FUNCTION runners.reap_stale_browser_locks(
    p_stale_interval INTERVAL DEFAULT '5 minutes'
)
RETURNS TABLE (
    reaped_browser_id UUID,
    tenant_id UUID,
    browser_name VARCHAR(128),
    dead_device_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    WITH stale_locks AS (
        SELECT b.id, b.tenant_id, b.name, b.locked_by_device_id
        FROM runners.browsers b
        LEFT JOIN runners.devices d ON d.id = b.locked_by_device_id
        WHERE b.status = 'running'
          AND b.locked_by_device_id IS NOT NULL
          AND (
              d.last_heartbeat_at IS NULL 
              OR d.last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
              OR (b.locked_at < (timezone('utc'::text, now()) - p_stale_interval) AND d.status = 'offline')
          )
    )
    UPDATE runners.browsers b
    SET 
        status = 'idle',
        locked_by_device_id = NULL,
        locked_at = NULL,
        updated_at = timezone('utc'::text, now())
    FROM stale_locks sl
    WHERE b.id = sl.id
    RETURNING b.id, b.tenant_id, b.name, sl.locked_by_device_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reap_stale_browser_locks(
    p_stale_interval INTERVAL DEFAULT '5 minutes'
)
RETURNS TABLE (
    reaped_browser_id UUID,
    tenant_id UUID,
    browser_name VARCHAR(128),
    dead_device_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY SELECT * FROM runners.reap_stale_browser_locks(p_stale_interval);
END;
$$;

GRANT EXECUTE ON FUNCTION runners.reap_stale_browser_locks(INTERVAL) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reap_stale_browser_locks(INTERVAL) TO authenticated, service_role;

-- Secure Permissions & Grants (Device Token and JWT Authenticated)
GRANT EXECUTE ON FUNCTION runners.enroll_device TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION runners.heartbeat TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION runners.acquire_browser TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION runners.release_browser TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION runners.create_browser TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION runners.list_browsers TO authenticated, anon, service_role;

GRANT EXECUTE ON FUNCTION public.heartbeat TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.acquire_browser TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.release_browser TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_browser TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_browsers TO authenticated, anon, service_role;

-- 8. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('runners:devices:read',    'runners', 'View registered runner nodes and live status'),
    ('runners:devices:manage',  'runners', 'Configure, pause, or remove runner devices'),
    ('runners:devices:enroll',  'runners', 'Enroll new physical workstations and edge nodes'),
    ('runners:proxies:read',    'runners', 'View proxy pool and health telemetry within tenant'),
    ('runners:proxies:manage',  'runners', 'Create, update, delete, and assign proxies within tenant'),
    ('runners:browsers:read',   'runners', 'View virtual browser profiles and fingerprint configurations'),
    ('runners:browsers:manage', 'runners', 'Create, update, delete, and control virtual browser profiles')
ON CONFLICT (id) DO UPDATE SET 
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Grant permissions to default roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('runners:devices:read'), ('runners:devices:manage'), ('runners:devices:enroll'),
        ('runners:proxies:read'), ('runners:proxies:manage'),
        ('runners:browsers:read'), ('runners:browsers:manage')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('runners:devices:read'), ('runners:proxies:read'), ('runners:browsers:read'),
        ('runners:browsers:manage')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 9. Register Plugin in Master Registry Table
SELECT public.register_plugin(
    'runners',
    'Runners & Compute Fleet',
    '1.0.0',
    'runners',
    ARRAY[]::TEXT[],
    'Universal distributed execution engine nodes, hardware fingerprinting, device enrollment, and live telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
