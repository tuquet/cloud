-- ============================================================================
-- SUPABASE MIGRATION: SYSTEM PLUGIN REGISTRY & LIFECYCLE MANAGEMENT
-- Version: 20260924000001
-- Target: Supabase / PostgreSQL (Base Core Infrastructure)
-- Description: Establishes the master plugin registry table and atomic RPC
--              functions to track, register, unregister, and validate on-demand plugins.
-- ============================================================================

-- 1. Plugin Status Enum
DO $$ BEGIN
    CREATE TYPE public.plugin_status AS ENUM ('installed', 'disabled', 'uninstalled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Master Plugin Registry Table
CREATE TABLE IF NOT EXISTS public.system_plugins (
    id VARCHAR(64) PRIMARY KEY,                  -- e.g. 'automa', 'storage', 'subscriptions', 'webhooks'
    name VARCHAR(128) NOT NULL,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    schema_name VARCHAR(64) NOT NULL UNIQUE,     -- e.g. 'automa', 'storage_mod', 'billing', 'events'
    status public.plugin_status NOT NULL DEFAULT 'installed',
    dependencies TEXT[] NOT NULL DEFAULT '{}',   -- e.g. ARRAY['storage']
    description TEXT,
    installed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    installed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.system_plugins IS 'Master registry tracking all dynamically installed plugins and schemas in the BaaS instance';

-- Indexing
CREATE INDEX IF NOT EXISTS idx_system_plugins_status ON public.system_plugins (status);
CREATE INDEX IF NOT EXISTS idx_system_plugins_schema ON public.system_plugins (schema_name);

-- 3. Enable RLS
ALTER TABLE public.system_plugins ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can view which plugins are installed
DROP POLICY IF EXISTS "system_plugins_select_all" ON public.system_plugins;
CREATE POLICY "system_plugins_select_all" ON public.system_plugins
    FOR SELECT TO authenticated
    USING (TRUE);

-- Only SuperAdmins or service_role can modify plugin registry
DROP POLICY IF EXISTS "system_plugins_manage_admin" ON public.system_plugins;
CREATE POLICY "system_plugins_manage_admin" ON public.system_plugins
    FOR ALL TO authenticated
    USING (
        auth.jwt() ->> 'role' = 'service_role'
        OR EXISTS (
            SELECT 1 FROM public.roles r
            JOIN public.member_roles mr ON mr.role_id = r.id
            JOIN public.tenant_members tm ON tm.id = mr.member_id
            WHERE tm.user_id = auth.uid() AND r.name = 'owner'
        )
    );

-- 4. RPC Functions for Plugin Lifecycle
-- 4.1. Register Plugin Function
CREATE OR REPLACE FUNCTION public.register_plugin(
    p_id VARCHAR(64),
    p_name VARCHAR(128),
    p_version VARCHAR(32),
    p_schema_name VARCHAR(64),
    p_dependencies TEXT[] DEFAULT '{}',
    p_description TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.system_plugins (
        id, name, version, schema_name, status, dependencies, description, installed_by, metadata, installed_at
    )
    VALUES (
        p_id, p_name, p_version, p_schema_name, 'installed', p_dependencies, p_description, auth.uid(), p_metadata, timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        version = EXCLUDED.version,
        schema_name = EXCLUDED.schema_name,
        status = 'installed',
        dependencies = EXCLUDED.dependencies,
        description = EXCLUDED.description,
        metadata = EXCLUDED.metadata,
        installed_at = timezone('utc'::text, now());
END;
$$;

-- 4.2. Unregister Plugin Function
CREATE OR REPLACE FUNCTION public.unregister_plugin(
    p_id VARCHAR(64)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_dependent_plugin TEXT;
BEGIN
    -- Dependency validation: Check if another active plugin depends on this one
    SELECT id INTO v_dependent_plugin
    FROM public.system_plugins
    WHERE status = 'installed' AND p_id = ANY(dependencies)
    LIMIT 1;

    IF v_dependent_plugin IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot unregister plugin %: Plugin % depends on it.', p_id, v_dependent_plugin
            USING ERRCODE = '23503';
    END IF;

    DELETE FROM public.system_plugins WHERE id = p_id;
END;
$$;

-- 4.3. Get Installed Plugins Function
CREATE OR REPLACE FUNCTION public.get_installed_plugins()
RETURNS TABLE (
    id VARCHAR(64),
    name VARCHAR(128),
    version VARCHAR(32),
    schema_name VARCHAR(64),
    status public.plugin_status,
    dependencies TEXT[],
    description TEXT,
    installed_at TIMESTAMPTZ,
    metadata JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sp.id, sp.name, sp.version, sp.schema_name, sp.status, sp.dependencies, sp.description, sp.installed_at, sp.metadata
    FROM public.system_plugins sp
    WHERE sp.status = 'installed'
    ORDER BY sp.installed_at ASC;
END;
$$;

-- 5. Add Plugin Management Permissions to Master Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('plugins:read',   'system', 'Inspect installed plugin registry and capabilities'),
    ('plugins:manage', 'system', 'Install, upgrade, and uninstall system plugins')
ON CONFLICT (id) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Grant permissions to system 'owner' role
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES ('plugins:read'), ('plugins:manage')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'owner'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Grant 'plugins:read' to system 'admin' role
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, 'plugins:read'
FROM public.roles r
WHERE r.tenant_id IS NULL AND r.name = 'admin'
ON CONFLICT (role_id, permission_id) DO NOTHING;
