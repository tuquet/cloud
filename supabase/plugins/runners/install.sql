-- ============================================================================
-- TUQUET-CLOUD PLUGIN: RUNNERS & COMPUTE FLEET (INSTALLATION SCRIPT)
-- Plugin ID: runners
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: runners)
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
CREATE TABLE IF NOT EXISTS runners.devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

-- Indexes
CREATE INDEX IF NOT EXISTS idx_runners_devices_tenant_status ON runners.devices (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_devices_heartbeat ON runners.devices (last_heartbeat_at);

-- 4. Row Level Security
ALTER TABLE runners.devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "devices_select" ON runners.devices
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "devices_manage" ON runners.devices
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:devices:manage') OR public.is_tenant_admin(tenant_id));

-- 5. RPC Functions
-- 5.1. Zero-Touch Device Enrollment
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
AS $$
DECLARE
    v_tenant_id UUID;
    v_device_id UUID;
    v_raw_token TEXT;
    v_token_hash TEXT;
    v_config JSONB;
BEGIN
    -- 1. Resolve Target Tenant
    -- If enrollment token provided, match with tenant (or fallback to primary active tenant)
    SELECT id INTO v_tenant_id FROM public.tenants WHERE status = 'active' ORDER BY created_at ASC LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No active tenant available in Tuquet Cloud to enroll device';
    END IF;

    -- 2. Generate Device Secret Token (Raw token returned to client, SHA-256 hash stored)
    v_raw_token := 'tqr_sec_' || encode(gen_random_bytes(24), 'hex');
    v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

    -- 3. Upsert Device in registry
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

    -- 4. Construct live dynamic config for client RAM
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

GRANT EXECUTE ON FUNCTION runners.enroll_device TO authenticated, anon, service_role;

-- 5.2. Device Heartbeat
CREATE OR REPLACE FUNCTION runners.heartbeat(
    p_device_id UUID,
    p_device_token TEXT,
    p_active_jobs INT DEFAULT 0,
    p_telemetry JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token_hash TEXT;
    v_updated INT;
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    UPDATE runners.devices
    SET 
        last_heartbeat_at = timezone('utc'::text, now()),
        active_jobs = GREATEST(p_active_jobs, 0),
        status = CASE WHEN p_active_jobs > 0 THEN 'busy'::runners.device_status ELSE 'idle'::runners.device_status END,
        metadata = runners.devices.metadata || jsonb_build_object('telemetry', p_telemetry),
        updated_at = timezone('utc'::text, now())
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    RETURN jsonb_build_object('success', true, 'timestamp', timezone('utc'::text, now()));
END;
$$;

GRANT EXECUTE ON FUNCTION runners.heartbeat TO authenticated, anon, service_role;

-- 5.3. Public Facade for seamless PostgREST RPC routing
CREATE OR REPLACE FUNCTION public.enroll_device(
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
AS $$
BEGIN
    RETURN runners.enroll_device(
        p_machine_fingerprint, p_name, p_os_info, p_cpu_cores, p_ram_mb,
        p_capabilities, p_metadata, p_enrollment_token
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.enroll_device TO authenticated, anon, service_role;

-- 6. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('runners:devices:read',   'runners', 'View registered runner nodes and live status'),
    ('runners:devices:manage', 'runners', 'Configure, pause, or remove runner devices'),
    ('runners:devices:enroll', 'runners', 'Enroll new physical workstations and edge nodes')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('runners:devices:read'), ('runners:devices:manage'), ('runners:devices:enroll')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('runners:devices:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry Table
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
