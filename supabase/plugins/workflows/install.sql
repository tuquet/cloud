-- ============================================================================
-- TUQUET-CLOUD PLUGIN: WORKFLOWS CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin ID: workflows
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: workflows)
-- Dependencies: ["runners"]
-- ============================================================================

-- 0. Graceful In-place Migration from Legacy schema 'automa' (if present)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'automa') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'workflows') THEN
        ALTER SCHEMA automa RENAME TO workflows;
    END IF;
END $$;

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS workflows;
GRANT USAGE ON SCHEMA workflows TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA workflows GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA workflows GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA workflows GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 2. Enums in schema workflows
DO $$ BEGIN
    CREATE TYPE workflows.workflow_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE workflows.campaign_status AS ENUM ('pending', 'queued', 'running', 'paused', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE workflows.log_level AS ENUM ('trace', 'debug', 'info', 'warn', 'error', 'fatal');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Tables in schema workflows
-- 3.1. Workflows Definitions
CREATE TABLE IF NOT EXISTS workflows.workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    status workflows.workflow_status NOT NULL DEFAULT 'draft',
    graph_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    variables JSONB NOT NULL DEFAULT '{}'::jsonb,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_workflows_workflows_tenant_id UNIQUE (tenant_id, id)
);

DO $$ BEGIN
    ALTER TABLE workflows.workflows ADD CONSTRAINT uq_workflows_workflows_tenant_id UNIQUE (tenant_id, id);
EXCEPTION
    WHEN duplicate_table OR duplicate_object THEN null;
END $$;

ALTER TABLE workflows.workflows ADD COLUMN IF NOT EXISTS status workflows.workflow_status NOT NULL DEFAULT 'draft';
ALTER TABLE workflows.workflows ADD COLUMN IF NOT EXISTS graph_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb;
ALTER TABLE workflows.workflows ADD COLUMN IF NOT EXISTS variables JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE workflows.workflows ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE workflows.workflows ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

COMMENT ON TABLE workflows.workflows IS '[Plugin: workflows] Visual flow graphs and AST node configurations for browser automation';

-- 3.2. Campaign Runs (Consumes Compute Node from schema runners)
CREATE TABLE IF NOT EXISTS workflows.campaign_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID,
    runner_id UUID,
    name VARCHAR(255) NOT NULL,
    status workflows.campaign_status NOT NULL DEFAULT 'pending',
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
    CONSTRAINT fk_workflows_campaign_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES workflows.workflows(tenant_id, id) ON DELETE SET NULL,
    CONSTRAINT fk_workflows_campaign_runner FOREIGN KEY (tenant_id, runner_id) REFERENCES runners.devices(tenant_id, id) ON DELETE SET NULL
);

-- 3.3. Execution Logs
CREATE TABLE IF NOT EXISTS workflows.execution_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    campaign_run_id UUID NOT NULL REFERENCES workflows.campaign_runs(id) ON DELETE CASCADE,
    node_id VARCHAR(64),
    step_name VARCHAR(128),
    level workflows.log_level NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3.4. Schedules
CREATE TABLE IF NOT EXISTS workflows.schedules (
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
    CONSTRAINT fk_workflows_schedules_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES workflows.workflows(tenant_id, id) ON DELETE CASCADE
);

-- 4. Composite Indexes
CREATE INDEX IF NOT EXISTS idx_workflows_workflows_tenant ON workflows.workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_campaigns_tenant ON workflows.campaign_runs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_logs_campaign ON workflows.execution_logs (tenant_id, campaign_run_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_logs_logged_at_brin ON workflows.execution_logs USING brin (logged_at);
CREATE INDEX IF NOT EXISTS idx_workflows_schedules_tenant ON workflows.schedules (tenant_id, is_active);

-- 5. Row Level Security
ALTER TABLE workflows.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.campaign_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workflows_select" ON workflows.workflows;
CREATE POLICY "workflows_select" ON workflows.workflows
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "workflows_manage" ON workflows.workflows;
CREATE POLICY "workflows_manage" ON workflows.workflows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:workflows:manage') OR public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "campaigns_select" ON workflows.campaign_runs;
CREATE POLICY "campaigns_select" ON workflows.campaign_runs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "campaigns_run" ON workflows.campaign_runs;
CREATE POLICY "campaigns_run" ON workflows.campaign_runs
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:campaigns:run') OR public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "logs_select" ON workflows.execution_logs;
CREATE POLICY "logs_select" ON workflows.execution_logs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "logs_insert" ON workflows.execution_logs;
CREATE POLICY "logs_insert" ON workflows.execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'workflows:campaigns:run') OR public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "schedules_select" ON workflows.schedules;
CREATE POLICY "schedules_select" ON workflows.schedules
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "schedules_manage" ON workflows.schedules;
CREATE POLICY "schedules_manage" ON workflows.schedules
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:campaigns:manage') OR public.is_tenant_admin(tenant_id));

-- 6. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('workflows:workflows:read',   'workflows', 'View workflows AST graphs'),
    ('workflows:workflows:manage', 'workflows', 'Create, edit, and delete workflows'),
    ('workflows:campaigns:read',   'workflows', 'View campaign runs and telemetry'),
    ('workflows:campaigns:run',    'workflows', 'Trigger workflow executions'),
    ('workflows:campaigns:manage', 'workflows', 'Configure campaign schedules'),
    ('workflows:logs:read',        'workflows', 'View execution telemetry logs'),
    -- Backward compatibility aliases
    ('automa:workflows:read',      'workflows', '[Legacy Alias] View workflows AST graphs'),
    ('automa:workflows:manage',    'workflows', '[Legacy Alias] Create, edit, and delete workflows'),
    ('automa:campaigns:read',      'workflows', '[Legacy Alias] View campaign runs and telemetry'),
    ('automa:campaigns:run',       'workflows', '[Legacy Alias] Trigger workflow executions'),
    ('automa:campaigns:manage',    'workflows', '[Legacy Alias] Configure campaign schedules'),
    ('automa:logs:read',           'workflows', '[Legacy Alias] View execution telemetry logs')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('workflows:workflows:read'), ('workflows:workflows:manage'),
        ('workflows:campaigns:read'), ('workflows:campaigns:run'), ('workflows:campaigns:manage'), ('workflows:logs:read'),
        ('automa:workflows:read'), ('automa:workflows:manage'),
        ('automa:campaigns:read'), ('automa:campaigns:run'), ('automa:campaigns:manage'), ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('workflows:workflows:read'), ('workflows:campaigns:read'), ('workflows:campaigns:run'), ('workflows:logs:read'),
        ('automa:workflows:read'), ('automa:campaigns:read'), ('automa:campaigns:run'), ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry Table
DELETE FROM public.system_plugins WHERE id = 'automa';

SELECT public.register_plugin(
    'workflows',
    'Workflows Cloud Bridge',
    '1.0.0',
    'workflows',
    ARRAY['runners']::TEXT[],
    'Distributed browser automation coordinator, batch campaign executions, and telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
