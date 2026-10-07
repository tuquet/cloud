-- ============================================================================
-- TUQUET-CLOUD MIGRATION: CLOUD BROWSER PROFILES & STORAGE SESSION SYNC
-- Version: 20261007000001
-- Target: Supabase / PostgreSQL (runners schema & storage)
-- Description: Implements central GoLogin-style cloud browser profiles with
--              deterministic C++ hardware fingerprinting, proxy pool integration,
--              distributed lease locking, and Supabase Storage session sync.
-- ============================================================================

-- 1. Create Runners Browsers Central Table
CREATE TABLE IF NOT EXISTS runners.browsers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    browser_type VARCHAR(64) NOT NULL DEFAULT 'chromium',
    engine_version VARCHAR(32) NOT NULL DEFAULT '148.0.7778.215',

    -- Deterministic C++ Native Fingerprint Specifications
    fingerprint_seed BIGINT NOT NULL DEFAULT floor(random() * 2147483647)::bigint,
    os_platform VARCHAR(32) NOT NULL DEFAULT 'windows', -- 'windows' | 'macos' | 'linux'
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
    webrtc_mode VARCHAR(32) NOT NULL DEFAULT 'proxy_shielded', -- 'disabled' | 'proxy_shielded' | 'real'

    -- Session Snapshot & Supabase Storage Synchronisation (.zip)
    storage_path TEXT, -- e.g. '<tenant_id>/<browser_id>.zip'
    storage_size_bytes BIGINT NOT NULL DEFAULT 0,
    storage_hash VARCHAR(64),
    cookies_count INT NOT NULL DEFAULT 0,
    last_synced_at TIMESTAMPTZ,

    -- Distributed Lease Lock & Execution State (Prevents Multi-Device Collisions)
    status VARCHAR(32) NOT NULL DEFAULT 'idle', -- 'idle' | 'running' | 'syncing' | 'error'
    locked_by_device_id UUID REFERENCES runners.devices(id) ON DELETE SET NULL,
    locked_at TIMESTAMPTZ,
    last_launched_at TIMESTAMPTZ,

    -- Timestamps & Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT chk_runners_browsers_status CHECK (status IN ('idle', 'running', 'syncing', 'error'))
);

COMMENT ON TABLE runners.browsers IS 'Central cloud inventory of virtual anti-detect browser profiles, hardware fingerprints, and session storage';

-- 2. Indexes for High Performance
CREATE INDEX IF NOT EXISTS idx_runners_browsers_tenant_status ON runners.browsers (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_browsers_locked ON runners.browsers (locked_by_device_id);
CREATE INDEX IF NOT EXISTS idx_runners_browsers_proxy_id ON runners.browsers (proxy_id);

-- 3. Row Level Security (RLS)
ALTER TABLE runners.browsers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "browsers_select" ON runners.browsers;
    DROP POLICY IF EXISTS "browsers_manage" ON runners.browsers;
EXCEPTION WHEN undefined_object THEN null;
END $$;

CREATE POLICY "browsers_select" ON runners.browsers
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "browsers_manage" ON runners.browsers
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:browsers:manage') OR public.is_tenant_admin(tenant_id));

-- 4. Register IAM Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('runners:browsers:read', 'runners', 'View virtual browser profiles and fingerprint configurations'),
    ('runners:browsers:manage', 'runners', 'Create, update, delete, and control virtual browser profiles')
ON CONFLICT (id) DO UPDATE SET 
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Grant permissions to default roles
DO $$
DECLARE
    r_owner UUID;
    r_admin UUID;
    r_member UUID;
BEGIN
    SELECT id INTO r_owner FROM public.roles WHERE name = 'owner' AND is_system = true LIMIT 1;
    SELECT id INTO r_admin FROM public.roles WHERE name = 'admin' AND is_system = true LIMIT 1;
    SELECT id INTO r_member FROM public.roles WHERE name = 'member' AND is_system = true LIMIT 1;

    IF r_owner IS NOT NULL THEN
        INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES 
            (r_owner, 'runners:browsers:read'),
            (r_owner, 'runners:browsers:manage')
        ON CONFLICT DO NOTHING;
    END IF;

    IF r_admin IS NOT NULL THEN
        INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES 
            (r_admin, 'runners:browsers:read'),
            (r_admin, 'runners:browsers:manage')
        ON CONFLICT DO NOTHING;
    END IF;

    IF r_member IS NOT NULL THEN
        INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES 
            (r_member, 'runners:browsers:read'),
            (r_member, 'runners:browsers:manage')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

GRANT ALL ON TABLE runners.browsers TO authenticated, service_role;

-- 5. Supabase Storage Bucket for Browser Profiles Session Archives
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'browser-profiles',
            'browser-profiles',
            false,
            268435456, -- 256 MB max per profile session archive
            ARRAY['application/zip', 'application/x-zip-compressed', 'application/octet-stream']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = EXCLUDED.public,
            file_size_limit = EXCLUDED.file_size_limit,
            allowed_mime_types = EXCLUDED.allowed_mime_types;
    END IF;
END $$;

-- Storage Objects Policies for browser-profiles bucket
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DROP POLICY IF EXISTS "storage_browser_profiles_select" ON storage.objects;
        CREATE POLICY "storage_browser_profiles_select" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id = 'browser-profiles' AND public.safe_cast_uuid((storage.foldername(name))[1]) IN (SELECT public.get_user_tenant_ids()));

        DROP POLICY IF EXISTS "storage_browser_profiles_insert" ON storage.objects;
        CREATE POLICY "storage_browser_profiles_insert" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id = 'browser-profiles' AND public.has_tenant_permission(public.safe_cast_uuid((storage.foldername(name))[1]), 'runners:browsers:manage'));

        DROP POLICY IF EXISTS "storage_browser_profiles_update" ON storage.objects;
        CREATE POLICY "storage_browser_profiles_update" ON storage.objects
            FOR UPDATE TO authenticated
            USING (bucket_id = 'browser-profiles' AND public.has_tenant_permission(public.safe_cast_uuid((storage.foldername(name))[1]), 'runners:browsers:manage'))
            WITH CHECK (bucket_id = 'browser-profiles' AND public.has_tenant_permission(public.safe_cast_uuid((storage.foldername(name))[1]), 'runners:browsers:manage'));

        DROP POLICY IF EXISTS "storage_browser_profiles_delete" ON storage.objects;
        CREATE POLICY "storage_browser_profiles_delete" ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id = 'browser-profiles' AND public.has_tenant_permission(public.safe_cast_uuid((storage.foldername(name))[1]), 'runners:browsers:manage'));
    END IF;
END $$;

-- 6. RPC FUNCTIONS: DISTRIBUTED LEASE ACQUISITION & RELEASE

-- 6.1. Acquire Browser Lease (Pre-Launch & Lock)
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
    v_is_stale BOOLEAN := false;
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- Authenticate Device
    SELECT tenant_id, name INTO v_device_tenant_id, v_device_name
    FROM runners.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- Fetch Browser Profile with Row Lock
    SELECT * INTO v_browser
    FROM runners.browsers
    WHERE id = p_browser_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_browser.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Browser profile not found in tenant');
    END IF;

    -- Concurrency Check: Verify if profile is currently locked by another device
    IF v_browser.status = 'running' AND v_browser.locked_by_device_id IS NOT NULL AND v_browser.locked_by_device_id <> p_device_id THEN
        -- Check if lock is stale (older than 15 minutes without update)
        IF v_browser.locked_at < (now() - interval '15 minutes') THEN
            v_is_stale := true;
        ELSE
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Browser profile is currently active on another device',
                'locked_by_device_id', v_browser.locked_by_device_id,
                'locked_at', v_browser.locked_at
            );
        END IF;
    END IF;

    -- Resolve Proxy Configuration
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

    -- Acquire Lease
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
        'recovered_stale_lock', v_is_stale,
        'device_name', v_device_name,
        'locked_at', timezone('utc'::text, now())
    );
END;
$$;

-- 6.2. Release Browser Lease (Post-Launch & Sync)
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
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- Authenticate Device
    SELECT tenant_id INTO v_device_tenant_id
    FROM runners.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- Fetch Browser Profile with Row Lock
    SELECT * INTO v_browser
    FROM runners.browsers
    WHERE id = p_browser_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_browser.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Browser profile not found');
    END IF;

    -- Release Lease and Update Storage Metadata
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
        'released_at', timezone('utc'::text, now())
    );
END;
$$;

-- 6.3. Create Cloud Browser Profile Helper
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
AS $$
DECLARE
    v_tenant_id UUID := p_tenant_id;
    v_seed BIGINT := p_fingerprint_seed;
    v_browser_id UUID;
BEGIN
    -- Resolve tenant if not specified
    IF v_tenant_id IS NULL AND auth.uid() IS NOT NULL THEN
        SELECT tm.tenant_id INTO v_tenant_id
        FROM public.tenant_members tm
        WHERE tm.user_id = auth.uid() AND tm.status = 'active'
        ORDER BY tm.created_at ASC
        LIMIT 1;
    END IF;

    IF v_tenant_id IS NULL THEN
        SELECT id INTO v_tenant_id FROM public.tenants WHERE status = 'active' ORDER BY created_at ASC LIMIT 1;
    END IF;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No active tenant found to create browser profile';
    END IF;

    -- Generate random 32-bit positive seed if not provided
    IF v_seed IS NULL OR v_seed <= 0 THEN
        v_seed := floor(random() * 2147483647)::bigint;
    END IF;

    INSERT INTO runners.browsers (
        tenant_id, name, fingerprint_seed, os_platform, browser_brand,
        proxy_id, custom_proxy, timezone, locale, cpu_cores, ram_gb
    )
    VALUES (
        v_tenant_id, p_name, v_seed, p_os_platform, p_browser_brand,
        p_proxy_id, p_custom_proxy, p_timezone, p_locale, p_cpu_cores, p_ram_gb
    )
    RETURNING id INTO v_browser_id;

    RETURN jsonb_build_object(
        'success', true,
        'browser_id', v_browser_id,
        'tenant_id', v_tenant_id,
        'name', p_name,
        'fingerprint_seed', v_seed,
        'os_platform', p_os_platform
    );
END;
$$;
