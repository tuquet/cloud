-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMA CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin ID: automa
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: automa)
-- Dependencies: ["runners"]
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS automa;
GRANT USAGE ON SCHEMA automa TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA automa GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA automa GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA automa GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 2. Enums in schema automa
DO $$ BEGIN
    CREATE TYPE automa.workflow_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE automa.campaign_status AS ENUM ('pending', 'queued', 'running', 'paused', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE automa.log_level AS ENUM ('trace', 'debug', 'info', 'warn', 'error', 'fatal');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Tables in schema automa
-- 3.1. Workflows
CREATE TABLE IF NOT EXISTS automa.workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    status automa.workflow_status NOT NULL DEFAULT 'draft',
    graph_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    variables JSONB NOT NULL DEFAULT '{}'::jsonb,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_automa_workflows_tenant_id UNIQUE (tenant_id, id)
);

COMMENT ON TABLE automa.workflows IS '[Plugin: automa] Visual flow graphs and AST node configurations';

-- 3.2. Campaign Runs (Consumes Compute Node from schema runners)
CREATE TABLE IF NOT EXISTS automa.campaign_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID,
    runner_id UUID,
    name VARCHAR(255) NOT NULL,
    status automa.campaign_status NOT NULL DEFAULT 'pending',
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
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT fk_automa_campaign_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES automa.workflows(tenant_id, id) ON DELETE SET NULL,
    CONSTRAINT fk_automa_campaign_runner FOREIGN KEY (tenant_id, runner_id) REFERENCES runners.devices(tenant_id, id) ON DELETE SET NULL
);

-- 3.3. Execution Logs
CREATE TABLE IF NOT EXISTS automa.execution_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    campaign_run_id UUID NOT NULL REFERENCES automa.campaign_runs(id) ON DELETE CASCADE,
    node_id VARCHAR(64),
    step_name VARCHAR(128),
    level automa.log_level NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3.4. Schedules
CREATE TABLE IF NOT EXISTS automa.schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID NOT NULL,
    name VARCHAR(128) NOT NULL,
    cron_expression VARCHAR(64) NOT NULL,
    timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT fk_automa_schedules_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES automa.workflows(tenant_id, id) ON DELETE CASCADE
);

-- 4. Composite Indexes
CREATE INDEX IF NOT EXISTS idx_automa_workflows_tenant ON automa.workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_tenant ON automa.campaign_runs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_logs_campaign ON automa.execution_logs (tenant_id, campaign_run_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_schedules_tenant ON automa.schedules (tenant_id, is_active);

-- 5. Row Level Security
ALTER TABLE automa.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.campaign_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE automa.schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workflows_select" ON automa.workflows
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

CREATE POLICY "workflows_manage" ON automa.workflows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:workflows:manage') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "campaigns_select" ON automa.campaign_runs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "campaigns_run" ON automa.campaign_runs
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:campaigns:run') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "logs_select" ON automa.execution_logs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "logs_insert" ON automa.execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'automa:campaigns:run') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "schedules_select" ON automa.schedules
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "schedules_manage" ON automa.schedules
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:campaigns:manage') OR public.is_tenant_admin(tenant_id));

-- 6. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('automa:workflows:read',   'automa', 'View workflows AST graphs'),
    ('automa:workflows:manage', 'automa', 'Create, edit, and delete workflows'),
    ('automa:campaigns:read',   'automa', 'View campaign runs and telemetry'),
    ('automa:campaigns:run',    'automa', 'Trigger workflow executions'),
    ('automa:campaigns:manage', 'automa', 'Configure campaign schedules'),
    ('automa:logs:read',        'automa', 'View execution telemetry logs')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('automa:workflows:read'), ('automa:workflows:manage'),
           ('automa:campaigns:read'), ('automa:campaigns:run'), ('automa:campaigns:manage'), ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('automa:workflows:read'), ('automa:campaigns:read'), ('automa:campaigns:run'), ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry Table
SELECT public.register_plugin(
    'automa',
    'Automa Cloud Bridge',
    '1.0.0',
    'automa',
    ARRAY['runners']::TEXT[],
    'Distributed browser automation coordinator, batch campaign runs, and telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
