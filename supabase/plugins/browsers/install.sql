-- ============================================================================
-- TUQUET-CLOUD PLUGIN: CLOUD BROWSER PROFILES & ANTIDETECT ENGINE CATALOG
-- Plugin ID: browsers
-- Version: 1.1.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: browsers)
-- Dependencies: ["core-iam"]
-- Specification: Ungoogled Chromium / adryfish/fingerprint-chromium 1:1 Alignment
--                Deterministic C++ PRNG (--fingerprint=<seed>), Official Releases,
--                Distributed Profile Leasing & Session Snapshot Sync
-- ============================================================================

-- 1. Create Dedicated Schema & Privileges
CREATE SCHEMA IF NOT EXISTS browsers;
GRANT USAGE ON SCHEMA browsers TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA browsers GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA browsers GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA browsers GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 1.1. Storage Helper for Validating Tenant Folder in browser-profiles Bucket
CREATE OR REPLACE FUNCTION public.is_valid_browser_storage_tenant(p_tenant_text TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_uuid UUID;
BEGIN
    IF p_tenant_text IS NULL OR length(p_tenant_text) < 32 THEN
        RETURN FALSE;
    END IF;

    BEGIN
        v_uuid := p_tenant_text::uuid;
    EXCEPTION WHEN OTHERS THEN
        RETURN FALSE;
    END;

    RETURN EXISTS (SELECT 1 FROM public.tenants WHERE id = v_uuid AND status = 'active');
END;
$$;
GRANT EXECUTE ON FUNCTION public.is_valid_browser_storage_tenant(TEXT) TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.is_valid_browser_storage_tenant(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT (
        p_tenant_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM public.tenants WHERE id = p_tenant_id AND status = 'active')
    );
$$;
GRANT EXECUTE ON FUNCTION public.is_valid_browser_storage_tenant(UUID) TO authenticated, anon, service_role;


-- 2. Storage Bucket for Browser Profile Session Archives (.zip, .tar.zst)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'browser-profiles',
            'browser-profiles',
            false,
            268435456, -- 256 MB max per profile archive
            ARRAY['application/zip', 'application/x-zip-compressed', 'application/octet-stream', 'application/zstd', 'application/x-tar']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = EXCLUDED.public,
            file_size_limit = EXCLUDED.file_size_limit,
            allowed_mime_types = EXCLUDED.allowed_mime_types;
    END IF;

        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DROP POLICY IF EXISTS "browser_profiles_storage_select" ON storage.objects;
        CREATE POLICY "browser_profiles_storage_select" ON storage.objects
            FOR SELECT TO authenticated, anon
            USING (
                bucket_id = 'browser-profiles'
                AND (
                    auth.role() = 'service_role'
                    OR public.is_valid_browser_storage_tenant(split_part(name, '/', 1))
                )
            );

        DROP POLICY IF EXISTS "browser_profiles_storage_insert" ON storage.objects;
        CREATE POLICY "browser_profiles_storage_insert" ON storage.objects
            FOR INSERT TO authenticated, anon
            WITH CHECK (
                bucket_id = 'browser-profiles'
                AND (
                    auth.role() = 'service_role'
                    OR public.is_valid_browser_storage_tenant(split_part(name, '/', 1))
                )
            );

        DROP POLICY IF EXISTS "browser_profiles_storage_update" ON storage.objects;
        CREATE POLICY "browser_profiles_storage_update" ON storage.objects
            FOR UPDATE TO authenticated, anon
            USING (
                bucket_id = 'browser-profiles'
                AND (
                    auth.role() = 'service_role'
                    OR public.is_valid_browser_storage_tenant(split_part(name, '/', 1))
                )
            )
            WITH CHECK (
                bucket_id = 'browser-profiles'
                AND (
                    auth.role() = 'service_role'
                    OR public.is_valid_browser_storage_tenant(split_part(name, '/', 1))
                )
            );

        DROP POLICY IF EXISTS "browser_profiles_storage_delete" ON storage.objects;
        CREATE POLICY "browser_profiles_storage_delete" ON storage.objects
            FOR DELETE TO authenticated, anon
            USING (
                bucket_id = 'browser-profiles'
                AND (
                    auth.role() = 'service_role'
                    OR public.is_valid_browser_storage_tenant(split_part(name, '/', 1))
                )
            );
    END IF;
END $$;

-- 3. Core Tables

-- 3.1. Central Engine Release Catalog (adryfish/fingerprint-chromium Distribution)
CREATE TABLE IF NOT EXISTS browsers.releases (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    version VARCHAR(32) NOT NULL,                       -- e.g. '148.0.7778.215'
    tag VARCHAR(32) NOT NULL,                           -- e.g. '148.0.7778.215'
    channel VARCHAR(32) NOT NULL DEFAULT 'lts',         -- 'lts', 'latest', 'archive'
    status VARCHAR(32) NOT NULL DEFAULT 'recommended',    -- 'recommended', 'buggy', 'deprecated', 'unverified'
    os_platform VARCHAR(32) NOT NULL,                    -- 'windows', 'linux', 'macos'
    arch VARCHAR(32) NOT NULL,                         -- 'x86_64', 'aarch64'
    asset_name TEXT NOT NULL,                            -- 'ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip'
    download_url TEXT NOT NULL,                          -- Official GitHub Release URL
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    sha256_checksum VARCHAR(64),
    is_recommended BOOLEAN NOT NULL DEFAULT false,
    notes TEXT,                                          -- Upstream notes & known issues
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT uq_browsers_releases_unique UNIQUE (version, channel, os_platform, arch)
);

COMMENT ON TABLE browsers.releases IS '[Plugin: browsers] Remote catalog of downloadable adryfish/fingerprint-chromium releases for CLI discovery and auto-installation';

CREATE INDEX IF NOT EXISTS idx_browsers_releases_lookup ON browsers.releases (os_platform, arch, channel);
CREATE INDEX IF NOT EXISTS idx_browsers_releases_version ON browsers.releases (version);

-- 3.2. Central Cloud Browser Profiles (Antidetect Identities - Streamlined for C++ Core)
CREATE TABLE IF NOT EXISTS browsers.profiles (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    group_name VARCHAR(64) NOT NULL DEFAULT 'default',
    tags TEXT[] DEFAULT '{}'::text[],

    -- C++ Engine & Version Target
    browser_type VARCHAR(64) NOT NULL DEFAULT 'ungoogled-chromium',
    engine_version VARCHAR(32) NOT NULL DEFAULT '148.0.7778.215',

    -- Core Deterministic C++ Fingerprint (--fingerprint=<seed>)
    -- In adryfish/fingerprint-chromium, this single seed deterministically drives:
    -- Canvas 2D noise, WebGL parameters, AudioContext, Font metrics, and Math.random PRNG
    fingerprint_seed BIGINT NOT NULL DEFAULT floor(random() * 2147483647)::bigint,

    -- Platform & Hardware Spoofing (--fingerprint-platform, --fingerprint-brand, etc.)
    os_platform VARCHAR(32) NOT NULL DEFAULT 'windows',
    os_version VARCHAR(64) NOT NULL DEFAULT '10.0.0',
    browser_brand VARCHAR(64) NOT NULL DEFAULT 'Chrome',
    cpu_cores INT NOT NULL DEFAULT 8 CHECK (cpu_cores >= 1),
    ram_gb INT NOT NULL DEFAULT 16 CHECK (ram_gb >= 1),

    -- Display Geometry & HiDPI Scaling (--window-size=W,H, --force-device-scale-factor)
    screen_width INT NOT NULL DEFAULT 1920,
    screen_height INT NOT NULL DEFAULT 1080,
    device_pixel_ratio NUMERIC(3, 2) NOT NULL DEFAULT 1.0,

    -- Localization, Headers & Client Hints
    timezone TEXT NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
    locale TEXT NOT NULL DEFAULT 'vi-VN',
    accept_languages TEXT NOT NULL DEFAULT 'vi-VN,vi,en-US,en',
    user_agent TEXT,
    sec_ch_ua TEXT,
    sec_ch_ua_platform VARCHAR(32) DEFAULT '"Windows"',
    sec_ch_ua_mobile BOOLEAN DEFAULT false,

    -- Network, Proxy & WebRTC STUN Shielding (--proxy-server, --disable-non-proxied-udp)
    proxy_id UUID,
    custom_proxy TEXT,
    change_ip_url TEXT,
    auto_timezone BOOLEAN NOT NULL DEFAULT true,
    auto_locale BOOLEAN NOT NULL DEFAULT true,
    webrtc_mode VARCHAR(32) NOT NULL DEFAULT 'proxy_shielded',

    -- Session Snapshot & Storage Sync (.zip)
    storage_path TEXT,
    storage_size_bytes BIGINT NOT NULL DEFAULT 0,
    storage_hash VARCHAR(64),
    cookies_count INT NOT NULL DEFAULT 0,
    last_synced_at TIMESTAMPTZ,

    -- Distributed Lease Lock & Execution State (Last-Write-Wins with In-Use Advisory)
    status VARCHAR(32) NOT NULL DEFAULT 'idle' CHECK (status IN ('idle', 'running', 'syncing', 'error')),
    locked_by_device_id UUID,
    locked_at TIMESTAMPTZ,
    last_launched_at TIMESTAMPTZ,

    -- Startup Options & Extensions (Stealth Default = [])
    startup_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
    extensions JSONB NOT NULL DEFAULT '[]'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE browsers.profiles IS '[Plugin: browsers] Multi-tenant inventory of virtual antidetect browser profiles aligned with adryfish/fingerprint-chromium';

CREATE INDEX IF NOT EXISTS idx_browsers_profiles_tenant_status ON browsers.profiles (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_browsers_profiles_tenant_group ON browsers.profiles (tenant_id, group_name);
CREATE INDEX IF NOT EXISTS idx_browsers_profiles_locked ON browsers.profiles (locked_by_device_id);
CREATE INDEX IF NOT EXISTS idx_browsers_profiles_proxy ON browsers.profiles (proxy_id);
CREATE INDEX IF NOT EXISTS idx_browsers_profiles_created_brin ON browsers.profiles USING brin (created_at);

-- 3.3. Fingerprint Baseline Templates (Presets)
CREATE TABLE IF NOT EXISTS browsers.fingerprint_templates (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE, -- NULL for public system presets
    name VARCHAR(128) NOT NULL,
    is_system BOOLEAN NOT NULL DEFAULT false,
    os_platform VARCHAR(32) NOT NULL DEFAULT 'windows',
    os_version VARCHAR(64) NOT NULL DEFAULT '10.0.0',
    browser_brand VARCHAR(64) NOT NULL DEFAULT 'Chrome',
    engine_version VARCHAR(32) NOT NULL DEFAULT '148.0.7778.215',
    screen_width INT NOT NULL DEFAULT 1920,
    screen_height INT NOT NULL DEFAULT 1080,
    device_pixel_ratio NUMERIC(3, 2) NOT NULL DEFAULT 1.0,
    cpu_cores INT NOT NULL DEFAULT 8,
    ram_gb INT NOT NULL DEFAULT 16,
    user_agent TEXT NOT NULL,
    sec_ch_ua TEXT NOT NULL,
    sec_ch_ua_platform VARCHAR(32) NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE browsers.fingerprint_templates IS '[Plugin: browsers] Baseline hardware fingerprint presets for one-click realistic profile generation';

CREATE INDEX IF NOT EXISTS idx_browsers_templates_system ON browsers.fingerprint_templates (is_system, os_platform);

-- 4. Row Level Security Policies

-- 4.1. releases policies (Public read for CLI)
ALTER TABLE browsers.releases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "releases_public_read" ON browsers.releases;
CREATE POLICY "releases_public_read" ON browsers.releases
    FOR SELECT TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "releases_service_manage" ON browsers.releases;
CREATE POLICY "releases_service_manage" ON browsers.releases
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- 4.2. profiles policies (Strict tenant isolation)
ALTER TABLE browsers.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select" ON browsers.profiles;
CREATE POLICY "profiles_select" ON browsers.profiles
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "profiles_manage" ON browsers.profiles;
CREATE POLICY "profiles_manage" ON browsers.profiles
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'browsers:profiles:manage') OR public.is_tenant_admin(tenant_id))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'browsers:profiles:manage') OR public.is_tenant_admin(tenant_id));

-- 4.3. fingerprint_templates policies
ALTER TABLE browsers.fingerprint_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "templates_select" ON browsers.fingerprint_templates;
CREATE POLICY "templates_select" ON browsers.fingerprint_templates
    FOR SELECT TO authenticated, anon
    USING (is_system = true OR (tenant_id IS NOT NULL AND public.is_tenant_member(tenant_id)));

DROP POLICY IF EXISTS "templates_manage" ON browsers.fingerprint_templates;
CREATE POLICY "templates_manage" ON browsers.fingerprint_templates
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'browsers:templates:manage') OR public.is_tenant_admin(tenant_id))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'browsers:templates:manage') OR public.is_tenant_admin(tenant_id));

-- 5. Business Logic: Distributed Lease & Lock Functions

-- 5.1. Acquire Profile Lock (with In-Use Advisory)
CREATE OR REPLACE FUNCTION browsers.acquire_profile(
    p_profile_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, browsers, workers
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_device_name TEXT;
    v_profile RECORD;
    v_in_use_warning BOOLEAN := false;
    v_active_device_id UUID;
    v_active_device_name TEXT;
    v_active_since TIMESTAMPTZ;
BEGIN
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

    -- Authenticate Device
    SELECT tenant_id, name INTO v_device_tenant_id, v_device_name
    FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- Fetch Profile with Row Lock
    SELECT * INTO v_profile
    FROM browsers.profiles
    WHERE id = p_profile_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_profile.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Profile not found in tenant');
    END IF;

    -- Detect active lock on another device
    IF v_profile.status = 'running' AND v_profile.locked_by_device_id IS NOT NULL AND v_profile.locked_by_device_id <> p_device_id THEN
        v_in_use_warning := true;
        v_active_device_id := v_profile.locked_by_device_id;
        v_active_since := v_profile.locked_at;

        SELECT name INTO v_active_device_name
        FROM workers.devices
        WHERE id = v_active_device_id;

        IF v_active_device_name IS NULL THEN
            v_active_device_name := 'Another Device';
        END IF;
    END IF;

    -- Transfer active session lease to requesting device
    UPDATE browsers.profiles
    SET 
        status = 'running',
        locked_by_device_id = p_device_id,
        locked_at = timezone('utc'::text, now()),
        last_launched_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = p_profile_id;

    RETURN jsonb_build_object(
        'success', true,
        'in_use_warning', v_in_use_warning,
        'profile', row_to_json(v_profile)::jsonb
    );
END;
$$;

-- 5.2. Release Profile Lock & Record Sync Metadata
CREATE OR REPLACE FUNCTION browsers.release_profile(
    p_profile_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT NULL,
    p_storage_hash VARCHAR(64) DEFAULT NULL,
    p_cookies_count INT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, browsers, workers
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_profile RECORD;
BEGIN
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

    -- Authenticate Device
    SELECT tenant_id INTO v_device_tenant_id
    FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    SELECT * INTO v_profile
    FROM browsers.profiles
    WHERE id = p_profile_id AND tenant_id = v_device_tenant_id
    FOR UPDATE;

    IF v_profile.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Profile not found in tenant');
    END IF;

    UPDATE browsers.profiles
    SET 
        status = 'idle',
        locked_by_device_id = NULL,
        locked_at = NULL,
        storage_path = COALESCE(p_storage_path, storage_path),
        storage_size_bytes = COALESCE(p_storage_size_bytes, storage_size_bytes),
        storage_hash = COALESCE(p_storage_hash, storage_hash),
        cookies_count = COALESCE(p_cookies_count, cookies_count),
        metadata = CASE WHEN p_metadata IS NOT NULL THEN metadata || p_metadata ELSE metadata END,
        last_synced_at = CASE WHEN p_storage_path IS NOT NULL THEN timezone('utc'::text, now()) ELSE last_synced_at END,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_profile_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 5.4. Upsert Profile (Local CLI -> Central Cloud Sync)
CREATE OR REPLACE FUNCTION browsers.upsert_profile(
    p_profile_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_name VARCHAR(128),
    p_fingerprint_seed BIGINT,
    p_screen_width INT DEFAULT 1920,
    p_screen_height INT DEFAULT 1080,
    p_device_pixel_ratio NUMERIC DEFAULT 1.0,
    p_os_platform VARCHAR(32) DEFAULT 'windows',
    p_cpu_cores INT DEFAULT 8,
    p_ram_gb INT DEFAULT 16,
    p_proxy TEXT DEFAULT NULL,
    p_timezone VARCHAR(64) DEFAULT NULL,
    p_locale VARCHAR(32) DEFAULT NULL,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT 0,
    p_storage_hash VARCHAR(64) DEFAULT NULL,
    p_cookies_count INT DEFAULT 0,
    p_metadata JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, browsers, workers
AS $$
DECLARE
    v_token_hash TEXT;
    v_device_tenant_id UUID;
    v_profile_id UUID;
BEGIN
    v_token_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

    -- Authenticate Device
    SELECT tenant_id INTO v_device_tenant_id
    FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_device_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    v_profile_id := COALESCE(p_profile_id, extensions.gen_random_uuid());

    INSERT INTO browsers.profiles (
        id, tenant_id, name, fingerprint_seed,
        screen_width, screen_height, device_pixel_ratio,
        os_platform, cpu_cores, ram_gb,
        custom_proxy, timezone, locale,
        storage_path, storage_size_bytes, storage_hash,
        cookies_count, metadata,
        status, last_synced_at, updated_at
    )
    VALUES (
        v_profile_id, v_device_tenant_id, p_name, p_fingerprint_seed,
        COALESCE(p_screen_width, 1920), COALESCE(p_screen_height, 1080), COALESCE(p_device_pixel_ratio, 1.0),
        COALESCE(p_os_platform, 'windows'), COALESCE(p_cpu_cores, 8), COALESCE(p_ram_gb, 16),
        p_proxy, p_timezone, p_locale,
        p_storage_path, COALESCE(p_storage_size_bytes, 0), p_storage_hash,
        COALESCE(p_cookies_count, 0), COALESCE(p_metadata, '{}'::jsonb),
        'idle', timezone('utc'::text, now()), timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        fingerprint_seed = EXCLUDED.fingerprint_seed,
        screen_width = EXCLUDED.screen_width,
        screen_height = EXCLUDED.screen_height,
        device_pixel_ratio = EXCLUDED.device_pixel_ratio,
        os_platform = EXCLUDED.os_platform,
        cpu_cores = EXCLUDED.cpu_cores,
        ram_gb = EXCLUDED.ram_gb,
        custom_proxy = COALESCE(EXCLUDED.custom_proxy, browsers.profiles.custom_proxy),
        timezone = COALESCE(EXCLUDED.timezone, browsers.profiles.timezone),
        locale = COALESCE(EXCLUDED.locale, browsers.profiles.locale),
        storage_path = COALESCE(EXCLUDED.storage_path, browsers.profiles.storage_path),
        storage_size_bytes = CASE WHEN EXCLUDED.storage_size_bytes > 0 THEN EXCLUDED.storage_size_bytes ELSE browsers.profiles.storage_size_bytes END,
        storage_hash = COALESCE(EXCLUDED.storage_hash, browsers.profiles.storage_hash),
        cookies_count = COALESCE(EXCLUDED.cookies_count, browsers.profiles.cookies_count),
        metadata = CASE WHEN p_metadata IS NOT NULL THEN browsers.profiles.metadata || p_metadata ELSE browsers.profiles.metadata END,
        last_synced_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'success', true,
        'profile_id', v_profile_id,
        'tenant_id', v_device_tenant_id,
        'storage_path', p_storage_path,
        'storage_hash', p_storage_hash
    );
END;
$$;

-- 5.3. Reap Stale Profile Locks
CREATE OR REPLACE FUNCTION browsers.reap_stale_profile_locks(
    p_stale_interval INTERVAL DEFAULT INTERVAL '10 minutes'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, browsers, workers
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE browsers.profiles p
    SET 
        status = 'idle',
        locked_by_device_id = NULL,
        locked_at = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE p.status = 'running'
      AND p.locked_at < (timezone('utc'::text, now()) - p_stale_interval);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- 6. Public PostgREST Facade Functions
CREATE OR REPLACE FUNCTION public.acquire_browser_profile(p_profile_id UUID, p_device_id UUID, p_device_token TEXT)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER AS $$
    SELECT browsers.acquire_profile(p_profile_id, p_device_id, p_device_token);
$$;

CREATE OR REPLACE FUNCTION public.release_browser_profile(
    p_profile_id UUID, p_device_id UUID, p_device_token TEXT,
    p_storage_path TEXT DEFAULT NULL, p_storage_size_bytes BIGINT DEFAULT NULL,
    p_storage_hash VARCHAR(64) DEFAULT NULL, p_cookies_count INT DEFAULT NULL, p_metadata JSONB DEFAULT NULL
)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER AS $$
    SELECT browsers.release_profile(p_profile_id, p_device_id, p_device_token, p_storage_path, p_storage_size_bytes, p_storage_hash, p_cookies_count, p_metadata);
$$;

DROP FUNCTION IF EXISTS public.upsert_browser_profile(UUID, UUID, TEXT, VARCHAR, BIGINT, INT, INT, NUMERIC, VARCHAR, INT, INT, TEXT, VARCHAR, VARCHAR, TEXT, BIGINT, VARCHAR, INT, JSONB);
CREATE OR REPLACE FUNCTION public.upsert_browser_profile(
    p_profile_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_name VARCHAR(128),
    p_fingerprint_seed BIGINT,
    p_screen_width INT DEFAULT 1920,
    p_screen_height INT DEFAULT 1080,
    p_device_pixel_ratio NUMERIC DEFAULT 1.0,
    p_os_platform VARCHAR(32) DEFAULT 'windows',
    p_cpu_cores INT DEFAULT 8,
    p_ram_gb INT DEFAULT 16,
    p_proxy TEXT DEFAULT NULL,
    p_timezone VARCHAR(64) DEFAULT NULL,
    p_locale VARCHAR(32) DEFAULT NULL,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT 0,
    p_storage_hash VARCHAR(64) DEFAULT NULL,
    p_cookies_count INT DEFAULT 0,
    p_metadata JSONB DEFAULT NULL
)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER AS $$
    SELECT browsers.upsert_profile(
        p_profile_id, p_device_id, p_device_token, p_name, p_fingerprint_seed,
        p_screen_width, p_screen_height, p_device_pixel_ratio,
        p_os_platform, p_cpu_cores, p_ram_gb,
        p_proxy, p_timezone, p_locale,
        p_storage_path, p_storage_size_bytes, p_storage_hash,
        p_cookies_count, p_metadata
    );
$$;

DROP FUNCTION IF EXISTS public.reap_stale_browser_locks(INTERVAL);
CREATE OR REPLACE FUNCTION public.reap_stale_browser_locks(p_stale_interval INTERVAL DEFAULT INTERVAL '10 minutes')
RETURNS INT LANGUAGE sql SECURITY DEFINER AS $$
    SELECT browsers.reap_stale_profile_locks(p_stale_interval);
$$;

-- 7. Register Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('browsers:releases:read',    'browsers', 'View browser engine releases and download links'),
    ('browsers:releases:manage',  'browsers', 'Publish, edit, and deprecate engine releases'),
    ('browsers:profiles:read',    'browsers', 'View antidetect browser profiles and fingerprints'),
    ('browsers:profiles:write',   'browsers', 'Create and modify antidetect browser profiles'),
    ('browsers:profiles:manage',  'browsers', 'Full administrative control over browser profiles'),
    ('browsers:templates:read',   'browsers', 'View fingerprint baseline templates'),
    ('browsers:templates:manage', 'browsers', 'Create and modify fingerprint templates')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to default roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('browsers:releases:read'), ('browsers:releases:manage'),
        ('browsers:profiles:read'), ('browsers:profiles:write'), ('browsers:profiles:manage'),
        ('browsers:templates:read'), ('browsers:templates:manage')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('browsers:releases:read'),
        ('browsers:profiles:read'), ('browsers:profiles:write'),
        ('browsers:templates:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 8. Seed Official adryfish/fingerprint-chromium Releases (1:1 with browser/manifest.json)

-- 8.1. Releases Catalog
INSERT INTO browsers.releases (
    version, tag, channel, status, os_platform, arch,
    asset_name, download_url, file_size_bytes, is_recommended, notes, published_at
)
VALUES 
    -- 148.0.7778.215 (Golden LTS)
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'windows', 'x86_64',
        'ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip',
        189767686, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'linux', 'x86_64',
        'ungoogled-chromium-148.0.7778.215-1-x86_64_linux.tar.xz',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium-148.0.7778.215-1-x86_64_linux.tar.xz',
        141269020, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'macos', 'x86_64',
        'ungoogled-chromium_148.0.7778.215-1.1_macos.dmg',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium_148.0.7778.215-1.1_macos.dmg',
        140187500, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    -- 150.0.7871.186 (Latest - Buggy)
    (
        '150.0.7871.186', '150.0.7871.186', 'latest', 'buggy', 'windows', 'x86_64',
        'ungoogled-chromium_150.0.7871.186-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/150.0.7871.186/ungoogled-chromium_150.0.7871.186-1.1_windows_x64.zip',
        193743241, false,
        'Upstream regression: SIGSEGV / Crashpad_NotConnectedToHandler in getImageData() / readPixels() (Issues #94 & #95). Not recommended for production.',
        '2026-10-02T14:02:29Z'
    ),
    (
        '150.0.7871.186', '150.0.7871.186', 'latest', 'buggy', 'linux', 'x86_64',
        'ungoogled-chromium-150.0.7871.186-1-x86_64_linux.tar.xz',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/150.0.7871.186/ungoogled-chromium-150.0.7871.186-1-x86_64_linux.tar.xz',
        145806232, false,
        'Upstream regression: SIGSEGV in getImageData() / readPixels(). Not recommended for production.',
        '2026-10-02T14:02:29Z'
    ),
    -- 144.0.7559.132 (Archive - Deprecated)
    (
        '144.0.7559.132', '144.0.7559.132', 'archive', 'deprecated', 'windows', 'x86_64',
        'ungoogled-chromium_144.0.7559.132-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/144.0.7559.132/ungoogled-chromium_144.0.7559.132-1.1_windows_x64.zip',
        176796270, false,
        'Introduced realistic WebGL parameter simulation. Deprecated manual --fingerprint-gpu-vendor.',
        '2026-02-27T09:02:24Z'
    ),
    (
        '144.0.7559.132', '144.0.7559.132', 'archive', 'deprecated', 'linux', 'x86_64',
        'ungoogled-chromium-144.0.7559.132-1-x86_64_linux.tar.xz',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/144.0.7559.132/ungoogled-chromium-144.0.7559.132-1-x86_64_linux.tar.xz',
        133493680, false,
        'Introduced realistic WebGL parameter simulation. Deprecated manual --fingerprint-gpu-vendor.',
        '2026-02-27T09:02:24Z'
    )
ON CONFLICT (version, channel, os_platform, arch) DO UPDATE SET
    download_url = EXCLUDED.download_url,
    asset_name = EXCLUDED.asset_name,
    file_size_bytes = EXCLUDED.file_size_bytes,
    is_recommended = EXCLUDED.is_recommended,
    status = EXCLUDED.status,
    notes = EXCLUDED.notes;

-- 8.2. Baseline Fingerprint Templates
INSERT INTO browsers.fingerprint_templates (
    name, is_system, os_platform, os_version, browser_brand, engine_version,
    screen_width, screen_height, device_pixel_ratio, cpu_cores, ram_gb,
    user_agent, sec_ch_ua, sec_ch_ua_platform
)
VALUES 
    (
        'Standard Windows 11 Desktop (1080p, 8-Core, 16GB)', true,
        'windows', '10.0.0', 'Chrome', '148.0.7778.215',
        1920, 1080, 1.0, 8, 16,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.7778.215 Safari/537.36',
        '"Chromium";v="148", "Not A(Brand";v="24", "Google Chrome";v="148"',
        '"Windows"'
    ),
    (
        'Retina macOS Sonoma Desktop (1440p, 10-Core, 16GB)', true,
        'macos', '14.5.0', 'Chrome', '148.0.7778.215',
        2560, 1440, 2.0, 10, 16,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.7778.215 Safari/537.36',
        '"Chromium";v="148", "Not A(Brand";v="24", "Google Chrome";v="148"',
        '"macOS"'
    )
ON CONFLICT DO NOTHING;

-- 9. Register Plugin in Master Registry Table
SELECT public.register_plugin(
    'browsers',
    'Cloud Browser Profiles & Antidetect Engine Catalog',
    '1.1.0',
    'browsers',
    ARRAY['core-iam']::TEXT[],
    'Virtual antidetect browser profiles (Ungoogled/adryfish), deterministic C++ PRNG fingerprints, remote engine releases catalog, and session storage sync',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);

-- 10. Backward Compatibility Views for legacy callers
DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'workers' AND table_name = 'browsers' AND table_type = 'BASE TABLE'
    ) THEN
        DROP TABLE IF EXISTS workers.browsers CASCADE;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'workers') THEN
        CREATE OR REPLACE VIEW workers.browsers AS SELECT * FROM browsers.profiles;
    END IF;
END $$;
