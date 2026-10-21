-- ============================================================================
-- TUQUET-CLOUD PLUGIN: WORKFLOWS CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin ID: workflows
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: workflows)
-- Dependencies: ["runners"]
-- Specification: 100% Official Automa AST & Package Blocks Specification
-- ============================================================================

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
    CONSTRAINT uq_workflows_workflows_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT chk_workflows_graph_structure CHECK (
        jsonb_typeof(graph_data) = 'object' AND
        graph_data ? 'nodes' AND
        graph_data ? 'edges' AND
        jsonb_typeof(graph_data->'nodes') = 'array' AND
        jsonb_typeof(graph_data->'edges') = 'array'
    )
);

COMMENT ON TABLE workflows.workflows IS '[Plugin: workflows] Visual flow graphs and AST node configurations for browser automation';

-- 3.2. Official Automa Reusable Block Packages (`workflows.packages`)
-- Conforms 100% to Automa Official Package model (PackageStore & BlockPackage.vue)
CREATE TABLE IF NOT EXISTS workflows.packages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    icon VARCHAR(128) NOT NULL DEFAULT 'mdiPackageVariantClosed',
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    is_external BOOLEAN NOT NULL DEFAULT FALSE,
    status workflows.workflow_status NOT NULL DEFAULT 'published',
    settings JSONB NOT NULL DEFAULT '{"asBlock": true}'::jsonb,
    inputs JSONB NOT NULL DEFAULT '[]'::jsonb,
    outputs JSONB NOT NULL DEFAULT '[]'::jsonb,
    variables JSONB NOT NULL DEFAULT '[]'::jsonb,
    data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_workflows_packages_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT chk_workflows_package_ast_structure CHECK (
        jsonb_typeof(data) = 'object' AND
        data ? 'nodes' AND
        data ? 'edges' AND
        jsonb_typeof(data->'nodes') = 'array' AND
        jsonb_typeof(data->'edges') = 'array'
    )
);

COMMENT ON TABLE workflows.packages IS '[Plugin: workflows] Official Automa Composite Block Packages for workflow modular assembly and marketplace sharing';

-- 3.3. Campaign Runs (Consumes Compute Node from schema runners)
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

-- 3.4. Execution Logs
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

-- 3.5. Schedules
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

-- 4. Composite & Specialized Indexes
CREATE INDEX IF NOT EXISTS idx_workflows_workflows_tenant ON workflows.workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_workflows_graph_gin ON workflows.workflows USING gin (graph_data jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_workflows_workflows_vars_gin ON workflows.workflows USING gin (variables jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_workflows_packages_tenant ON workflows.packages (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_packages_data_gin ON workflows.packages USING gin (data jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_workflows_campaigns_tenant ON workflows.campaign_runs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_campaigns_params_gin ON workflows.campaign_runs USING gin (parameters jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_workflows_logs_campaign ON workflows.execution_logs (tenant_id, campaign_run_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflows_logs_logged_at_brin ON workflows.execution_logs USING brin (logged_at);

CREATE INDEX IF NOT EXISTS idx_workflows_schedules_tenant ON workflows.schedules (tenant_id, is_active);

-- 5. Business Logic Functions & Procedures

-- 5.1. High-Performance Atomic Campaign Claiming (`FOR UPDATE SKIP LOCKED`)
CREATE OR REPLACE FUNCTION workflows.claim_next_campaign_run(
    p_runner_id UUID,
    p_batch_size INT DEFAULT 1
)
RETURNS SETOF workflows.campaign_runs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflows, public, pg_temp
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM runners.devices
    WHERE id = p_runner_id AND status IN ('idle', 'running');

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Runner % is invalid or offline', p_runner_id;
    END IF;

    RETURN QUERY
    WITH candidate_runs AS (
        SELECT id
        FROM workflows.campaign_runs
        WHERE tenant_id = v_tenant_id
          AND status = 'queued'
        ORDER BY created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE workflows.campaign_runs r
    SET 
        runner_id = p_runner_id,
        status = 'running',
        started_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    FROM candidate_runs c
    WHERE r.id = c.id
    RETURNING r.*;
END;
$$;

-- 5.2. Automated Dead-Run Reaper (Self-Healing Fleet Manager)
CREATE OR REPLACE FUNCTION workflows.reap_stale_campaign_runs(
    p_stale_interval INTERVAL DEFAULT INTERVAL '10 minutes'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workflows, runners, public, pg_temp
AS $$
DECLARE
    v_reaped_count INT := 0;
BEGIN
    WITH dead_runners AS (
        SELECT id, tenant_id
        FROM runners.devices
        WHERE last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
           OR status = 'offline'
    ),
    stale_runs AS (
        SELECT r.id
        FROM workflows.campaign_runs r
        JOIN dead_runners d ON r.runner_id = d.id AND r.tenant_id = d.tenant_id
        WHERE r.status = 'running'
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE workflows.campaign_runs r
    SET 
        status = 'failed',
        error_message = 'Runner node heartbeat timed out (Dead Lease Reaper)',
        ended_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    FROM stale_runs s
    WHERE r.id = s.id;

    GET DIAGNOSTICS v_reaped_count = ROW_COUNT;
    RETURN v_reaped_count;
END;
$$;

-- 5.3. Real-Time Notification Trigger for Queued Campaigns
CREATE OR REPLACE FUNCTION workflows.notify_campaign_queued()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status = 'queued' AND (OLD IS NULL OR OLD.status <> 'queued') THEN
        PERFORM pg_notify(
            'workflows_campaign_dispatch',
            json_build_object(
                'campaign_run_id', NEW.id,
                'tenant_id', NEW.tenant_id,
                'workflow_id', NEW.workflow_id
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workflows_campaign_notify ON workflows.campaign_runs;
CREATE TRIGGER trg_workflows_campaign_notify
    AFTER INSERT OR UPDATE OF status ON workflows.campaign_runs
    FOR EACH ROW
    EXECUTE FUNCTION workflows.notify_campaign_queued();

-- 6. Row Level Security
ALTER TABLE workflows.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.campaign_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows.schedules ENABLE ROW LEVEL SECURITY;

-- 6.1. workflows policies
DROP POLICY IF EXISTS "workflows_select" ON workflows.workflows;
CREATE POLICY "workflows_select" ON workflows.workflows
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "workflows_manage" ON workflows.workflows;
CREATE POLICY "workflows_manage" ON workflows.workflows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:workflows:manage') OR public.is_tenant_admin(tenant_id));

-- 6.2. packages policies
DROP POLICY IF EXISTS "packages_select" ON workflows.packages;
CREATE POLICY "packages_select" ON workflows.packages
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "packages_manage" ON workflows.packages;
CREATE POLICY "packages_manage" ON workflows.packages
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:packages:manage') OR public.is_tenant_admin(tenant_id));

-- 6.3. campaigns policies
DROP POLICY IF EXISTS "campaigns_select" ON workflows.campaign_runs;
CREATE POLICY "campaigns_select" ON workflows.campaign_runs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "campaigns_run" ON workflows.campaign_runs;
CREATE POLICY "campaigns_run" ON workflows.campaign_runs
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:campaigns:run') OR public.is_tenant_admin(tenant_id));

-- 6.4. logs policies
DROP POLICY IF EXISTS "logs_select" ON workflows.execution_logs;
CREATE POLICY "logs_select" ON workflows.execution_logs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "logs_insert" ON workflows.execution_logs;
CREATE POLICY "logs_insert" ON workflows.execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'workflows:campaigns:run') OR public.is_tenant_admin(tenant_id));

-- 6.5. schedules policies
DROP POLICY IF EXISTS "schedules_select" ON workflows.schedules;
CREATE POLICY "schedules_select" ON workflows.schedules
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "schedules_manage" ON workflows.schedules;
CREATE POLICY "schedules_manage" ON workflows.schedules
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'workflows:campaigns:manage') OR public.is_tenant_admin(tenant_id));

-- 7. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('workflows:workflows:read',   'workflows', 'View workflows AST graphs'),
    ('workflows:workflows:manage', 'workflows', 'Create, edit, and delete workflows'),
    ('workflows:packages:read',    'workflows', 'View reusable block packages'),
    ('workflows:packages:manage',  'workflows', 'Create, edit, and publish block packages'),
    ('workflows:campaigns:read',   'workflows', 'View campaign runs and telemetry'),
    ('workflows:campaigns:run',    'workflows', 'Trigger workflow executions'),
    ('workflows:campaigns:manage', 'workflows', 'Configure campaign schedules'),
    ('workflows:logs:read',        'workflows', 'View execution telemetry logs')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('workflows:workflows:read'), ('workflows:workflows:manage'),
        ('workflows:packages:read'), ('workflows:packages:manage'),
        ('workflows:campaigns:read'), ('workflows:campaigns:run'), ('workflows:campaigns:manage'), ('workflows:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('workflows:workflows:read'),
        ('workflows:packages:read'),
        ('workflows:campaigns:read'), ('workflows:campaigns:run'), ('workflows:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 8. Register Plugin in Master Registry Table
DELETE FROM public.system_plugins WHERE id = 'automa';

SELECT public.register_plugin(
    'workflows',
    'Workflows Cloud Bridge',
    '1.0.0',
    'workflows',
    ARRAY['runners']::TEXT[],
    'Distributed browser automation coordinator, composite package blocks, batch campaign executions, and telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
