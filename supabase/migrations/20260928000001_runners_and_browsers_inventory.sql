-- ============================================================================
-- TUQUET-CLOUD MIGRATION: RUNNER FLEET & NODE-LOCAL BROWSER INVENTORY
-- Version: 20260928000001
-- Target: Supabase / PostgreSQL (runners schema)
-- Description: Establishes the Central Control Plane for tracking physical/edge 
--              worker nodes (runners.devices) and their node-local browser profiles
--              (runners.node_browsers) without storing heavy user data on the cloud.
-- ============================================================================

-- 1. Ensure Schema & Enums exist
CREATE SCHEMA IF NOT EXISTS runners;
GRANT USAGE ON SCHEMA runners TO authenticated, service_role, anon;

DO $$ BEGIN
    CREATE TYPE runners.device_status AS ENUM ('offline', 'idle', 'busy', 'maintenance', 'disabled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Physical Workstations & Edge Worker Nodes Table
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

COMMENT ON TABLE runners.devices IS 'Registered physical PCs, laptops, and edge worker nodes reporting to Tuquet Cloud';

CREATE INDEX IF NOT EXISTS idx_runners_devices_tenant_status ON runners.devices (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_devices_heartbeat ON runners.devices (last_heartbeat_at);

-- 3. Node-Local Browser Profile Inventory Table
-- Profiles reside strictly on the local workstation disk (Node-Local Resource Affinity)
-- Only metadata, identity, and status are reported to the central cloud hub
CREATE TABLE IF NOT EXISTS runners.node_browsers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES runners.devices(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    local_id TEXT NOT NULL,
    name TEXT NOT NULL,
    browser_type VARCHAR(64) NOT NULL DEFAULT 'chromium',
    status VARCHAR(32) NOT NULL DEFAULT 'idle', -- 'idle' | 'running' | 'error'
    user_agent TEXT,
    timezone TEXT,
    proxy TEXT,
    current_job_id TEXT,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_runners_node_browsers_device_local_id UNIQUE (device_id, local_id)
);

COMMENT ON TABLE runners.node_browsers IS 'Central inventory of browser profiles owned and hosted locally by each worker PC';

CREATE INDEX IF NOT EXISTS idx_runners_node_browsers_device ON runners.node_browsers (device_id);
CREATE INDEX IF NOT EXISTS idx_runners_node_browsers_tenant_status ON runners.node_browsers (tenant_id, status);

-- 4. Row Level Security
ALTER TABLE runners.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE runners.node_browsers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "devices_select" ON runners.devices;
    DROP POLICY IF EXISTS "devices_manage" ON runners.devices;
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

CREATE POLICY "node_browsers_select" ON runners.node_browsers
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "node_browsers_manage" ON runners.node_browsers
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:devices:manage') OR public.is_tenant_admin(tenant_id));

-- 5. RPC FUNCTIONS FOR WORKSTATION TELEMETRY

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
    -- Resolve Target Tenant
    -- Priority 1: User authenticated via JWT
    IF auth.uid() IS NOT NULL THEN
        SELECT tm.tenant_id INTO v_tenant_id
        FROM public.tenant_members tm
        WHERE tm.user_id = auth.uid() AND tm.status = 'active'
        ORDER BY tm.created_at ASC
        LIMIT 1;
    END IF;

    -- Priority 2: Enrollment token matching tenant slug or ID
    IF v_tenant_id IS NULL AND p_enrollment_token IS NOT NULL AND p_enrollment_token <> '' THEN
        SELECT id INTO v_tenant_id
        FROM public.tenants
        WHERE (slug = p_enrollment_token OR id::text = p_enrollment_token) AND status = 'active'
        LIMIT 1;
    END IF;

    -- Priority 3: Fallback to the first active tenant
    IF v_tenant_id IS NULL THEN
        SELECT id INTO v_tenant_id FROM public.tenants WHERE status = 'active' ORDER BY created_at ASC LIMIT 1;
    END IF;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No active tenant available in Tuquet Cloud to enroll device';
    END IF;

    -- Generate Device Secret Token (Raw token returned to client once; SHA-256 hash stored)
    v_raw_token := 'tqr_sec_' || encode(gen_random_bytes(24), 'hex');
    v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

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
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials or token');
    END IF;

    RETURN jsonb_build_object('success', true, 'timestamp', timezone('utc'::text, now()));
END;
$$;

-- 5.3. Report Node-Local Browser Profiles Inventory
-- Replaces/upserts the full list of local browser profiles on this workstation
CREATE OR REPLACE FUNCTION runners.report_browser_inventory(
    p_device_id UUID,
    p_device_token TEXT,
    p_browsers JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token_hash TEXT;
    v_tenant_id UUID;
    v_item JSONB;
    v_count INT := 0;
    v_local_ids TEXT[] := ARRAY[]::TEXT[];
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- Verify device authenticity
    SELECT tenant_id INTO v_tenant_id 
    FROM runners.devices 
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    -- Update last heartbeat
    UPDATE runners.devices 
    SET last_heartbeat_at = timezone('utc'::text, now()), updated_at = timezone('utc'::text, now())
    WHERE id = p_device_id;

    -- Process array of local browsers
    IF p_browsers IS NOT NULL AND jsonb_typeof(p_browsers) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_browsers) LOOP
            IF v_item->>'id' IS NOT NULL THEN
                v_local_ids := array_append(v_local_ids, v_item->>'id');

                INSERT INTO runners.node_browsers (
                    device_id, tenant_id, local_id, name, browser_type,
                    status, user_agent, timezone, proxy, current_job_id,
                    last_seen_at, updated_at
                )
                VALUES (
                    p_device_id,
                    v_tenant_id,
                    v_item->>'id',
                    COALESCE(v_item->>'name', v_item->>'id'),
                    COALESCE(v_item->>'browserType', 'chromium'),
                    COALESCE(v_item->>'status', 'idle'),
                    v_item->>'userAgent',
                    v_item->>'timezone',
                    v_item->>'proxy',
                    v_item->>'currentJobId',
                    timezone('utc'::text, now()),
                    timezone('utc'::text, now())
                )
                ON CONFLICT (device_id, local_id)
                DO UPDATE SET
                    name = EXCLUDED.name,
                    browser_type = EXCLUDED.browser_type,
                    status = EXCLUDED.status,
                    user_agent = EXCLUDED.user_agent,
                    timezone = EXCLUDED.timezone,
                    proxy = EXCLUDED.proxy,
                    current_job_id = EXCLUDED.current_job_id,
                    last_seen_at = timezone('utc'::text, now()),
                    updated_at = timezone('utc'::text, now());

                v_count := v_count + 1;
            END IF;
        END LOOP;

        -- Remove local profiles that were deleted from the workstation
        IF array_length(v_local_ids, 1) > 0 THEN
            DELETE FROM runners.node_browsers
            WHERE device_id = p_device_id AND NOT (local_id = ANY(v_local_ids));
        ELSE
            DELETE FROM runners.node_browsers
            WHERE device_id = p_device_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'device_id', p_device_id,
        'synced_count', v_count,
        'timestamp', timezone('utc'::text, now())
    );
END;
$$;

-- 5.4. Public PostgREST Facades
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

CREATE OR REPLACE FUNCTION public.heartbeat(
    p_device_id UUID,
    p_device_token TEXT,
    p_active_jobs INT DEFAULT 0,
    p_telemetry JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.heartbeat(p_device_id, p_device_token, p_active_jobs, p_telemetry);
END;
$$;

CREATE OR REPLACE FUNCTION public.report_browser_inventory(
    p_device_id UUID,
    p_device_token TEXT,
    p_browsers JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.report_browser_inventory(p_device_id, p_device_token, p_browsers);
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.enroll_device TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.heartbeat TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.report_browser_inventory TO authenticated, anon, service_role;

GRANT ALL ON TABLE runners.devices TO authenticated, service_role;
GRANT ALL ON TABLE runners.node_browsers TO authenticated, service_role;

-- ============================================================================
-- 6. AUTOMA CLOUD WORKFLOW SCHEMA
-- Multi-Tenant Workflow graph, Variables, Tables & Row data
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS automa;
GRANT USAGE ON SCHEMA automa TO authenticated, service_role;

-- 6.1. Automa Workflows Table
CREATE TABLE IF NOT EXISTS automa.workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    local_id VARCHAR(64),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    icon TEXT,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_automa_workflows_tenant_local UNIQUE (tenant_id, local_id),
    CONSTRAINT uq_automa_workflows_tenant_id UNIQUE (tenant_id, id)
);

CREATE INDEX IF NOT EXISTS idx_automa_workflows_tenant ON automa.workflows (tenant_id);
CREATE INDEX IF NOT EXISTS idx_automa_workflows_created_by ON automa.workflows (created_by);

-- 6.2. Automa Shared Variables Table
CREATE TABLE IF NOT EXISTS automa.variables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_automa_variables_tenant_key UNIQUE (tenant_id, key)
);

CREATE INDEX IF NOT EXISTS idx_automa_variables_tenant ON automa.variables (tenant_id);

-- 6.3. Automa Tables & Rows
CREATE TABLE IF NOT EXISTS automa.tables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    columns JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_automa_tables_tenant_name UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_automa_tables_tenant ON automa.tables (tenant_id);

CREATE TABLE IF NOT EXISTS automa.table_rows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES automa.tables(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    row_index INT NOT NULL DEFAULT 0,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_automa_table_rows_table ON automa.table_rows (table_id);
CREATE INDEX IF NOT EXISTS idx_automa_table_rows_tenant ON automa.table_rows (tenant_id);

-- 6.4. Row-Level Security for Automa Schema
ALTER TABLE automa.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.variables ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.table_rows ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "workflows_select" ON automa.workflows;
    DROP POLICY IF EXISTS "workflows_manage" ON automa.workflows;
    DROP POLICY IF EXISTS "variables_select" ON automa.variables;
    DROP POLICY IF EXISTS "variables_manage" ON automa.variables;
    DROP POLICY IF EXISTS "tables_select" ON automa.tables;
    DROP POLICY IF EXISTS "tables_manage" ON automa.tables;
    DROP POLICY IF EXISTS "table_rows_select" ON automa.table_rows;
    DROP POLICY IF EXISTS "table_rows_manage" ON automa.table_rows;
EXCEPTION WHEN undefined_object THEN null;
END $$;

CREATE POLICY "workflows_select" ON automa.workflows
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "workflows_manage" ON automa.workflows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:workflows:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "variables_select" ON automa.variables
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "variables_manage" ON automa.variables
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:variables:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "tables_select" ON automa.tables
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "tables_manage" ON automa.tables
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:tables:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "table_rows_select" ON automa.table_rows
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "table_rows_manage" ON automa.table_rows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:tables:manage') OR public.is_tenant_admin(tenant_id));

-- Grants for Automa Schema
GRANT ALL ON TABLE automa.workflows TO authenticated, service_role;
GRANT ALL ON TABLE automa.variables TO authenticated, service_role;
GRANT ALL ON TABLE automa.tables TO authenticated, service_role;
GRANT ALL ON TABLE automa.table_rows TO authenticated, service_role;

