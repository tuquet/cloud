-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMA CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin Name: automa
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL (Multi-tenant RBAC Extension)
-- Description: Installs distributed browser automation schemas, runners, 
--              campaign execution pools, telemetry logs, and RLS policies.
-- Invariant: Prefix automa_* on all tables, enums, and permissions.
-- ============================================================================

-- Helper function for updated_at column timestamp refresh if not already defined
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. ENUMS
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE public.automa_workflow_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.automa_runner_status AS ENUM ('offline', 'idle', 'running', 'busy', 'disconnected', 'maintenance');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.automa_campaign_status AS ENUM ('pending', 'queued', 'running', 'paused', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.automa_log_level AS ENUM ('trace', 'debug', 'info', 'warn', 'error', 'fatal');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ----------------------------------------------------------------------------
-- 2. TABLE DEFINITIONS (PREFIX: automa_*)
-- ----------------------------------------------------------------------------

-- 2.1. Workflows: AST đồ thị flow canvas JSON (nodes, edges, config)
CREATE TABLE IF NOT EXISTS public.automa_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    status public.automa_workflow_status NOT NULL DEFAULT 'draft',
    graph_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    variables JSONB NOT NULL DEFAULT '{}'::jsonb,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

COMMENT ON TABLE public.automa_workflows IS '[Plugin: automa] Workflow flow graphs and visual execution definitions';

-- 2.2. Runners: Máy trạm thực thi Automa Core (Rust daemon nodes)
CREATE TABLE IF NOT EXISTS public.automa_runners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    machine_fingerprint VARCHAR(128) NOT NULL,
    status public.automa_runner_status NOT NULL DEFAULT 'offline',
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    os_info VARCHAR(128),
    ip_address INET,
    max_concurrency INT NOT NULL DEFAULT 1 CHECK (max_concurrency >= 1),
    active_tasks INT NOT NULL DEFAULT 0 CHECK (active_tasks >= 0),
    capabilities JSONB NOT NULL DEFAULT '["browser", "http", "gui"]'::jsonb,
    last_heartbeat_at TIMESTAMPTZ,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_automa_runner_tenant_fingerprint UNIQUE (tenant_id, machine_fingerprint)
);

COMMENT ON TABLE public.automa_runners IS '[Plugin: automa] Registered distributed Rust runner nodes executing automation tasks';

-- 2.3. Campaign Runs: Các phiên thực thi quy trình theo lô
CREATE TABLE IF NOT EXISTS public.automa_campaign_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID REFERENCES public.automa_workflows(id) ON DELETE SET NULL,
    runner_id UUID REFERENCES public.automa_runners(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    status public.automa_campaign_status NOT NULL DEFAULT 'pending',
    total_tasks INT NOT NULL DEFAULT 0 CHECK (total_tasks >= 0),
    completed_tasks INT NOT NULL DEFAULT 0 CHECK (completed_tasks >= 0),
    failed_tasks INT NOT NULL DEFAULT 0 CHECK (failed_tasks >= 0),
    parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    result_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    error_message TEXT,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    triggered_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_campaign_runs IS '[Plugin: automa] Batch execution campaign sessions and live task counters';

-- 2.4. Execution Logs: Nhật ký và telemetry chi tiết
CREATE TABLE IF NOT EXISTS public.automa_execution_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    campaign_run_id UUID NOT NULL REFERENCES public.automa_campaign_runs(id) ON DELETE CASCADE,
    node_id VARCHAR(64),
    step_name VARCHAR(128),
    level public.automa_log_level NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_execution_logs IS '[Plugin: automa] Realtime telemetry and step-by-step logs for campaign runs';

-- 2.5. Schedules: Lập lịch chạy tự động theo biểu thức Cron
CREATE TABLE IF NOT EXISTS public.automa_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID NOT NULL REFERENCES public.automa_workflows(id) ON DELETE CASCADE,
    name VARCHAR(128) NOT NULL,
    cron_expression VARCHAR(64) NOT NULL,
    timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_schedules IS '[Plugin: automa] Cron triggers for automated headless workflow execution';

-- ----------------------------------------------------------------------------
-- 3. COMPOSITE INDEXES
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_automa_workflows_tenant_created ON public.automa_workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_workflows_deleted_at ON public.automa_workflows (tenant_id, deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_automa_runners_tenant_status ON public.automa_runners (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_automa_runners_heartbeat ON public.automa_runners (tenant_id, last_heartbeat_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_tenant_status ON public.automa_campaign_runs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_workflow ON public.automa_campaign_runs (workflow_id);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_runner ON public.automa_campaign_runs (runner_id);
CREATE INDEX IF NOT EXISTS idx_automa_logs_tenant_campaign ON public.automa_execution_logs (tenant_id, campaign_run_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_logs_level ON public.automa_execution_logs (tenant_id, level);
CREATE INDEX IF NOT EXISTS idx_automa_schedules_tenant_active ON public.automa_schedules (tenant_id, is_active);

-- ----------------------------------------------------------------------------
-- 4. TRIGGERS (TIMESTAMP REFRESH)
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS set_automa_workflows_updated_at ON public.automa_workflows;
CREATE TRIGGER set_automa_workflows_updated_at
    BEFORE UPDATE ON public.automa_workflows
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_automa_runners_updated_at ON public.automa_runners;
CREATE TRIGGER set_automa_runners_updated_at
    BEFORE UPDATE ON public.automa_runners
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_automa_campaigns_updated_at ON public.automa_campaign_runs;
CREATE TRIGGER set_automa_campaigns_updated_at
    BEFORE UPDATE ON public.automa_campaign_runs
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_automa_schedules_updated_at ON public.automa_schedules;
CREATE TRIGGER set_automa_schedules_updated_at
    BEFORE UPDATE ON public.automa_schedules
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.automa_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_runners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_campaign_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_schedules ENABLE ROW LEVEL SECURITY;

-- 5.1. Workflows Policies
DROP POLICY IF EXISTS "automa_workflows_select_active" ON public.automa_workflows;
CREATE POLICY "automa_workflows_select_active" ON public.automa_workflows
    FOR SELECT TO authenticated
    USING (
        deleted_at IS NULL 
        AND public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:workflows:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

DROP POLICY IF EXISTS "automa_workflows_insert" ON public.automa_workflows;
CREATE POLICY "automa_workflows_insert" ON public.automa_workflows
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_tenant_permission(tenant_id, 'automa:workflows:manage')
        OR public.is_tenant_admin(tenant_id)
    );

DROP POLICY IF EXISTS "automa_workflows_update" ON public.automa_workflows;
CREATE POLICY "automa_workflows_update" ON public.automa_workflows
    FOR UPDATE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:workflows:manage')
        OR public.is_tenant_admin(tenant_id)
    );

DROP POLICY IF EXISTS "automa_workflows_delete" ON public.automa_workflows;
CREATE POLICY "automa_workflows_delete" ON public.automa_workflows
    FOR DELETE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:workflows:manage')
        OR public.is_tenant_admin(tenant_id)
    );

-- 5.2. Runners Policies
DROP POLICY IF EXISTS "automa_runners_select" ON public.automa_runners;
CREATE POLICY "automa_runners_select" ON public.automa_runners
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:runners:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

DROP POLICY IF EXISTS "automa_runners_manage" ON public.automa_runners;
CREATE POLICY "automa_runners_manage" ON public.automa_runners
    FOR ALL TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:runners:manage')
        OR public.is_tenant_admin(tenant_id)
    );

-- 5.3. Campaign Runs Policies
DROP POLICY IF EXISTS "automa_campaigns_select" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_select" ON public.automa_campaign_runs
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:campaigns:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

DROP POLICY IF EXISTS "automa_campaigns_insert" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_insert" ON public.automa_campaign_runs
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:run')
        OR public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
        OR public.is_tenant_admin(tenant_id)
    );

DROP POLICY IF EXISTS "automa_campaigns_update" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_update" ON public.automa_campaign_runs
    FOR UPDATE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
        OR public.is_tenant_admin(tenant_id)
    );

DROP POLICY IF EXISTS "automa_campaigns_delete" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_delete" ON public.automa_campaign_runs
    FOR DELETE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
        OR public.is_tenant_admin(tenant_id)
    );

-- 5.4. Execution Logs Policies
DROP POLICY IF EXISTS "automa_logs_select" ON public.automa_execution_logs;
CREATE POLICY "automa_logs_select" ON public.automa_execution_logs
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:logs:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

DROP POLICY IF EXISTS "automa_logs_insert" ON public.automa_execution_logs;
CREATE POLICY "automa_logs_insert" ON public.automa_execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_tenant_member(tenant_id)
    );

-- 5.5. Schedules Policies
DROP POLICY IF EXISTS "automa_schedules_select" ON public.automa_schedules;
CREATE POLICY "automa_schedules_select" ON public.automa_schedules
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:campaigns:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

DROP POLICY IF EXISTS "automa_schedules_manage" ON public.automa_schedules;
CREATE POLICY "automa_schedules_manage" ON public.automa_schedules
    FOR ALL TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
        OR public.is_tenant_admin(tenant_id)
    );

-- ----------------------------------------------------------------------------
-- 6. PERMISSIONS & RBAC DICTIONARY REGISTRATION
-- ----------------------------------------------------------------------------
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('automa:workflows:read',   'automa', 'View workflows and AST canvas definitions'),
    ('automa:workflows:manage', 'automa', 'Create, edit, publish, and delete workflows'),
    ('automa:runners:read',     'automa', 'View registered runner nodes and statuses'),
    ('automa:runners:manage',   'automa', 'Register, configure, and maintain runner nodes'),
    ('automa:campaigns:read',   'automa', 'View batch campaign history and live progress'),
    ('automa:campaigns:run',    'automa', 'Trigger and run workflow campaigns'),
    ('automa:campaigns:manage', 'automa', 'Configure campaign parameters, concurrency, and schedules'),
    ('automa:logs:read',        'automa', 'View execution telemetry and logs')
ON CONFLICT (id) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Grant all permissions to system 'owner' and 'admin' roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automa:workflows:read'),
        ('automa:workflows:manage'),
        ('automa:runners:read'),
        ('automa:runners:manage'),
        ('automa:campaigns:read'),
        ('automa:campaigns:run'),
        ('automa:campaigns:manage'),
        ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Grant read and run permissions to system 'member' role
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automa:workflows:read'),
        ('automa:runners:read'),
        ('automa:campaigns:read'),
        ('automa:campaigns:run'),
        ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;
