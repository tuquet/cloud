-- ============================================================================
-- TUQUET-CLOUD MIGRATION: DISTRIBUTED PROXY POOL & NETWORK MANAGEMENT
-- Version: 20261006000001
-- Target: Supabase / PostgreSQL (runners schema)
-- Description: Establishes the Central Proxy Pool management layer in schema runners,
--              enabling tenant-isolated proxy pooling, health tracking, protocol 
--              classification, and dynamic assignment to runners & browser instances.
-- ============================================================================

-- 1. Create Enums for Proxies
DO $$ BEGIN
    CREATE TYPE runners.proxy_protocol AS ENUM ('http', 'https', 'socks5');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE runners.proxy_status AS ENUM ('active', 'dead', 'slow', 'banned', 'testing');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE runners.proxy_type AS ENUM ('datacenter', 'residential', 'mobile', 'isp');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Central Proxy Pool Inventory Table
CREATE TABLE IF NOT EXISTS runners.proxies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    protocol runners.proxy_protocol NOT NULL DEFAULT 'http',
    host VARCHAR(255) NOT NULL,
    port INT NOT NULL CHECK (port > 0 AND port <= 65535),
    username VARCHAR(128),
    password_hash TEXT,
    status runners.proxy_status NOT NULL DEFAULT 'active',
    proxy_type runners.proxy_type NOT NULL DEFAULT 'datacenter',
    country_code VARCHAR(8),
    city VARCHAR(64),
    latency_ms INT,
    last_checked_at TIMESTAMPTZ,
    assigned_device_id UUID REFERENCES runners.devices(id) ON DELETE SET NULL,
    assigned_browser_id UUID REFERENCES runners.node_browsers(id) ON DELETE SET NULL,
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_runners_proxies_tenant_host_port UNIQUE (tenant_id, protocol, host, port, username)
);

COMMENT ON TABLE runners.proxies IS 'Central pool of residential, mobile, datacenter, and SOCKS5 proxies managed per tenant';

-- 3. Enhance runners.node_browsers to link with central proxy pool
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'runners' AND table_name = 'node_browsers' AND column_name = 'proxy_id'
    ) THEN
        ALTER TABLE runners.node_browsers 
        ADD COLUMN proxy_id UUID REFERENCES runners.proxies(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 4. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_runners_proxies_tenant_status ON runners.proxies (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_runners_proxies_country ON runners.proxies (country_code);
CREATE INDEX IF NOT EXISTS idx_runners_proxies_assigned_device ON runners.proxies (assigned_device_id);
CREATE INDEX IF NOT EXISTS idx_runners_proxies_assigned_browser ON runners.proxies (assigned_browser_id);
CREATE INDEX IF NOT EXISTS idx_runners_node_browsers_proxy_id ON runners.node_browsers (proxy_id);

-- 5. Row-Level Security (RLS)
ALTER TABLE runners.proxies ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "proxies_select" ON runners.proxies;
    DROP POLICY IF EXISTS "proxies_manage" ON runners.proxies;
EXCEPTION WHEN undefined_object THEN null;
END $$;

CREATE POLICY "proxies_select" ON runners.proxies
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "proxies_manage" ON runners.proxies
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'runners:proxies:manage') OR public.is_tenant_admin(tenant_id));

-- 6. Permissions Registration
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('runners:proxies:read', 'runners', 'View proxy pool and health telemetry within tenant'),
    ('runners:proxies:manage', 'runners', 'Create, update, delete, and assign proxies within tenant')
ON CONFLICT (id) DO UPDATE SET 
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Grant permissions to default system roles
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
            (r_owner, 'runners:proxies:read'),
            (r_owner, 'runners:proxies:manage')
        ON CONFLICT DO NOTHING;
    END IF;

    IF r_admin IS NOT NULL THEN
        INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES 
            (r_admin, 'runners:proxies:read'),
            (r_admin, 'runners:proxies:manage')
        ON CONFLICT DO NOTHING;
    END IF;

    IF r_member IS NOT NULL THEN
        INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES 
            (r_member, 'runners:proxies:read')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- Grants
GRANT ALL ON TABLE runners.proxies TO authenticated, service_role;

-- 7. RPC Helper Functions for Edge Runners

-- 7.1. Atomic Proxy Health Report
CREATE OR REPLACE FUNCTION runners.report_proxy_health(
    p_proxy_id UUID,
    p_latency_ms INT,
    p_status VARCHAR(32) DEFAULT 'active',
    p_error TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id UUID;
    v_updated INT;
BEGIN
    -- Verify tenant membership
    SELECT tenant_id INTO v_tenant_id FROM runners.proxies WHERE id = p_proxy_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Proxy not found');
    END IF;

    IF auth.uid() IS NOT NULL AND NOT public.is_tenant_member(v_tenant_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    UPDATE runners.proxies
    SET 
        latency_ms = p_latency_ms,
        status = p_status::runners.proxy_status,
        last_checked_at = timezone('utc'::text, now()),
        metadata = CASE 
            WHEN p_error IS NOT NULL THEN runners.proxies.metadata || jsonb_build_object('last_error', p_error, 'error_at', now())
            ELSE runners.proxies.metadata
        END,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_proxy_id;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN jsonb_build_object('success', v_updated > 0, 'proxy_id', p_proxy_id);
END;
$$;

-- 7.2. Claim / Check out an Active Proxy for a Device or Browser
CREATE OR REPLACE FUNCTION runners.claim_proxy(
    p_device_id UUID,
    p_browser_id UUID DEFAULT NULL,
    p_protocol VARCHAR(16) DEFAULT NULL,
    p_country_code VARCHAR(8) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id UUID;
    v_proxy_record RECORD;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM runners.devices WHERE id = p_device_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Device not found');
    END IF;

    -- Select and lock one active, unassigned or least recently used proxy
    SELECT * INTO v_proxy_record
    FROM runners.proxies
    WHERE tenant_id = v_tenant_id
      AND status = 'active'
      AND (p_protocol IS NULL OR protocol = p_protocol::runners.proxy_protocol)
      AND (p_country_code IS NULL OR country_code = p_country_code)
      AND (assigned_device_id IS NULL OR assigned_device_id = p_device_id)
    ORDER BY 
        CASE WHEN assigned_device_id = p_device_id THEN 0 ELSE 1 END,
        last_checked_at ASC NULLS FIRST
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_proxy_record.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No available proxy found matching criteria');
    END IF;

    -- Assign proxy to device / browser
    UPDATE runners.proxies
    SET 
        assigned_device_id = p_device_id,
        assigned_browser_id = p_browser_id,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_proxy_record.id;

    IF p_browser_id IS NOT NULL THEN
        UPDATE runners.node_browsers
        SET 
            proxy_id = v_proxy_record.id,
            proxy = v_proxy_record.protocol::text || '://' || 
                CASE WHEN v_proxy_record.username IS NOT NULL THEN v_proxy_record.username || ':***@' ELSE '' END || 
                v_proxy_record.host || ':' || v_proxy_record.port,
            updated_at = timezone('utc'::text, now())
        WHERE id = p_browser_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'proxy_id', v_proxy_record.id,
        'name', v_proxy_record.name,
        'protocol', v_proxy_record.protocol,
        'host', v_proxy_record.host,
        'port', v_proxy_record.port,
        'username', v_proxy_record.username,
        'country_code', v_proxy_record.country_code
    );
END;
$$;

-- 7.3. Batch Sync Proxies from Workstation
CREATE OR REPLACE FUNCTION runners.sync_proxies(
    p_device_id UUID,
    p_device_token TEXT,
    p_proxies JSONB
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
BEGIN
    v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');

    -- Verify device authenticity
    SELECT tenant_id INTO v_tenant_id 
    FROM runners.devices 
    WHERE id = p_device_id AND device_token_hash = v_token_hash;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device credentials');
    END IF;

    IF p_proxies IS NOT NULL AND jsonb_typeof(p_proxies) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_proxies) LOOP
            IF v_item->>'host' IS NOT NULL AND v_item->>'port' IS NOT NULL THEN
                INSERT INTO runners.proxies (
                    tenant_id, name, protocol, host, port, username,
                    status, proxy_type, country_code, city, latency_ms,
                    assigned_device_id, tags, metadata, last_checked_at
                )
                VALUES (
                    v_tenant_id,
                    COALESCE(v_item->>'name', (v_item->>'host') || ':' || (v_item->>'port')),
                    COALESCE(v_item->>'protocol', 'http')::runners.proxy_protocol,
                    v_item->>'host',
                    (v_item->>'port')::INT,
                    v_item->>'username',
                    COALESCE(v_item->>'status', 'active')::runners.proxy_status,
                    COALESCE(v_item->>'proxyType', 'datacenter')::runners.proxy_type,
                    v_item->>'countryCode',
                    v_item->>'city',
                    (v_item->>'latencyMs')::INT,
                    p_device_id,
                    COALESCE(v_item->'tags', '[]'::jsonb),
                    COALESCE(v_item->'metadata', '{}'::jsonb),
                    timezone('utc'::text, now())
                )
                ON CONFLICT (tenant_id, protocol, host, port, username)
                DO UPDATE SET
                    name = EXCLUDED.name,
                    status = EXCLUDED.status,
                    latency_ms = COALESCE(EXCLUDED.latency_ms, runners.proxies.latency_ms),
                    country_code = COALESCE(EXCLUDED.country_code, runners.proxies.country_code),
                    city = COALESCE(EXCLUDED.city, runners.proxies.city),
                    last_checked_at = timezone('utc'::text, now()),
                    updated_at = timezone('utc'::text, now());

                v_count := v_count + 1;
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'synced_count', v_count);
END;
$$;
