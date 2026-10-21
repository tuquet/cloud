-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMATION CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin ID: automation
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: automation)
-- Dependencies: ["runners"]
-- Specification: 100% Official Automa AST & Package Blocks Specification
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS automation;
GRANT USAGE ON SCHEMA automation TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA automation GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA automation GRANT ALL ON FUNCTIONS TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA automation GRANT ALL ON SEQUENCES TO authenticated, service_role;

-- 2. Enums in schema automation
DO $$ BEGIN
    CREATE TYPE automation.workflow_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE automation.job_status AS ENUM ('pending', 'queued', 'running', 'paused', 'completed', 'failed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE automation.log_level AS ENUM ('trace', 'debug', 'info', 'warn', 'error', 'fatal');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Tables in schema automation

-- 3.1. Workflows Definitions
CREATE TABLE IF NOT EXISTS automation.workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    status automation.workflow_status NOT NULL DEFAULT 'draft',
    graph_data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    variables JSONB NOT NULL DEFAULT '{}'::jsonb,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_automation_workflows_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT chk_automation_graph_structure CHECK (
        jsonb_typeof(graph_data) = 'object' AND
        graph_data ? 'nodes' AND
        graph_data ? 'edges' AND
        jsonb_typeof(graph_data->'nodes') = 'array' AND
        jsonb_typeof(graph_data->'edges') = 'array'
    )
);

COMMENT ON TABLE automation.workflows IS '[Plugin: automation] Visual flow graphs and AST node configurations for browser automation';

-- 3.2. Official Automa Reusable Block Packages (`automation.packages`)
-- Conforms 100% to Automa Official Package model (PackageStore & BlockPackage.vue)
CREATE TABLE IF NOT EXISTS automation.packages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    icon VARCHAR(128) NOT NULL DEFAULT 'mdiPackageVariantClosed',
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    is_external BOOLEAN NOT NULL DEFAULT FALSE,
    status automation.workflow_status NOT NULL DEFAULT 'published',
    settings JSONB NOT NULL DEFAULT '{"asBlock": true}'::jsonb,
    inputs JSONB NOT NULL DEFAULT '[]'::jsonb,
    outputs JSONB NOT NULL DEFAULT '[]'::jsonb,
    variables JSONB NOT NULL DEFAULT '[]'::jsonb,
    data JSONB NOT NULL DEFAULT '{"nodes": [], "edges": []}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL,
    CONSTRAINT uq_automation_packages_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT chk_automation_package_ast_structure CHECK (
        jsonb_typeof(data) = 'object' AND
        data ? 'nodes' AND
        data ? 'edges' AND
        jsonb_typeof(data->'nodes') = 'array' AND
        jsonb_typeof(data->'edges') = 'array'
    )
);

COMMENT ON TABLE automation.packages IS '[Plugin: automation] Official Automa Composite Block Packages for workflow modular assembly and marketplace sharing';

-- 3.3. jobs (Consumes Compute Node from schema runners)
CREATE TABLE IF NOT EXISTS automation.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID,
    worker_id UUID,
    name VARCHAR(255) NOT NULL,
    status automation.job_status NOT NULL DEFAULT 'pending',
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
    CONSTRAINT fk_automation_job_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES automation.workflows(tenant_id, id) ON DELETE SET NULL,
    CONSTRAINT fk_automation_job_worker FOREIGN KEY (tenant_id, worker_id) REFERENCES workers.devices(tenant_id, id) ON DELETE SET NULL
);

-- 3.4. Execution Logs
CREATE TABLE IF NOT EXISTS automation.execution_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES automation.jobs(id) ON DELETE CASCADE,
    node_id VARCHAR(64),
    step_name VARCHAR(128),
    level automation.log_level NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3.5. Schedules
CREATE TABLE IF NOT EXISTS automation.schedules (
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
    CONSTRAINT fk_automation_schedules_workflow FOREIGN KEY (tenant_id, workflow_id) REFERENCES automation.workflows(tenant_id, id) ON DELETE CASCADE
);

-- 4. Composite & Specialized Indexes
CREATE INDEX IF NOT EXISTS idx_automation_workflows_tenant ON automation.workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_workflows_graph_gin ON automation.workflows USING gin (graph_data jsonb_path_ops);
CREATE INDEX IF NOT EXISTS idx_automation_workflows_vars_gin ON automation.workflows USING gin (variables jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_automation_packages_tenant ON automation.packages (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_packages_data_gin ON automation.packages USING gin (data jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_automation_jobs_tenant ON automation.jobs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_jobs_params_gin ON automation.jobs USING gin (parameters jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_automation_logs_job ON automation.execution_logs (tenant_id, job_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_logs_logged_at_brin ON automation.execution_logs USING brin (logged_at);

CREATE INDEX IF NOT EXISTS idx_automation_schedules_tenant ON automation.schedules (tenant_id, is_active);

-- 5. Business Logic Functions & Procedures

-- 5.1. High-Performance Atomic job Claiming (`FOR UPDATE SKIP LOCKED`)
CREATE OR REPLACE FUNCTION automation.claim_next_job(
    p_worker_id UUID,
    p_batch_size INT DEFAULT 1
)
RETURNS SETOF automation.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM workers.devices
    WHERE id = p_worker_id AND status IN ('idle', 'running');

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Runner % is invalid or offline', p_worker_id;
    END IF;

    RETURN QUERY
    WITH candidate_runs AS (
        SELECT id
        FROM automation.jobs
        WHERE tenant_id = v_tenant_id
          AND status = 'queued'
        ORDER BY created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE automation.jobs r
    SET 
        worker_id = p_worker_id,
        status = 'running',
        started_at = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    FROM candidate_runs c
    WHERE r.id = c.id
    RETURNING r.*;
END;
$$;

-- 5.2. Automated Dead-Run Reaper (Self-Healing Fleet Manager)
CREATE OR REPLACE FUNCTION automation.reap_stale_jobs(
    p_stale_interval INTERVAL DEFAULT INTERVAL '10 minutes'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, runners, public, pg_temp
AS $$
DECLARE
    v_reaped_count INT := 0;
BEGIN
    WITH dead_runners AS (
        SELECT id, tenant_id
        FROM workers.devices
        WHERE last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
           OR status = 'offline'
    ),
    stale_runs AS (
        SELECT r.id
        FROM automation.jobs r
        JOIN dead_runners d ON r.worker_id = d.id AND r.tenant_id = d.tenant_id
        WHERE r.status = 'running'
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE automation.jobs r
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

-- 5.3. Real-Time Notification Trigger for Queued jobs
CREATE OR REPLACE FUNCTION automation.notify_job_queued()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status = 'queued' AND (OLD IS NULL OR OLD.status <> 'queued') THEN
        PERFORM pg_notify(
            'automation_job_dispatch',
            json_build_object(
                'job_id', NEW.id,
                'tenant_id', NEW.tenant_id,
                'workflow_id', NEW.workflow_id
            )::text
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_automation_job_notify ON automation.jobs;
CREATE TRIGGER trg_automation_job_notify
    AFTER INSERT OR UPDATE OF status ON automation.jobs
    FOR EACH ROW
    EXECUTE FUNCTION automation.notify_job_queued();

-- 6. Row Level Security
ALTER TABLE automation.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation.packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation.execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation.schedules ENABLE ROW LEVEL SECURITY;

-- 6.1. workflows policies
DROP POLICY IF EXISTS "workflows_select" ON automation.workflows;
CREATE POLICY "workflows_select" ON automation.workflows
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "workflows_manage" ON automation.workflows;
CREATE POLICY "workflows_manage" ON automation.workflows
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automation:workflows:manage') OR public.is_tenant_admin(tenant_id));

-- 6.2. packages policies
DROP POLICY IF EXISTS "packages_select" ON automation.packages;
CREATE POLICY "packages_select" ON automation.packages
    FOR SELECT TO authenticated
    USING (deleted_at IS NULL AND public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "packages_manage" ON automation.packages;
CREATE POLICY "packages_manage" ON automation.packages
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automation:packages:manage') OR public.is_tenant_admin(tenant_id));

-- 6.3. jobs policies
DROP POLICY IF EXISTS "jobs_select" ON automation.jobs;
CREATE POLICY "jobs_select" ON automation.jobs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "jobs_run" ON automation.jobs;
CREATE POLICY "jobs_run" ON automation.jobs
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automation:jobs:run') OR public.is_tenant_admin(tenant_id));

-- 6.4. logs policies
DROP POLICY IF EXISTS "logs_select" ON automation.execution_logs;
CREATE POLICY "logs_select" ON automation.execution_logs
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "logs_insert" ON automation.execution_logs;
CREATE POLICY "logs_insert" ON automation.execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'automation:jobs:run') OR public.is_tenant_admin(tenant_id));

-- 6.5. schedules policies
DROP POLICY IF EXISTS "schedules_select" ON automation.schedules;
CREATE POLICY "schedules_select" ON automation.schedules
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "schedules_manage" ON automation.schedules;
CREATE POLICY "schedules_manage" ON automation.schedules
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automation:jobs:manage') OR public.is_tenant_admin(tenant_id));

-- 7. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('automation:workflows:read',   'automation', 'View automation workflow AST graphs'),
    ('automation:workflows:manage', 'automation', 'Create, edit, and delete automation workflows'),
    ('automation:packages:read',    'automation', 'View reusable composite block packages'),
    ('automation:packages:manage',  'automation', 'Create, edit, and publish block packages'),
    ('automation:jobs:read',   'automation', 'View jobs and telemetry'),
    ('automation:jobs:run',    'automation', 'Trigger automation workflow executions'),
    ('automation:jobs:manage', 'automation', 'Configure job schedules'),
    ('automation:logs:read',        'automation', 'View execution telemetry logs')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

-- Grant permissions to roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automation:workflows:read'), ('automation:workflows:manage'),
        ('automation:packages:read'), ('automation:packages:manage'),
        ('automation:jobs:read'), ('automation:jobs:run'), ('automation:jobs:manage'), ('automation:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automation:workflows:read'),
        ('automation:packages:read'),
        ('automation:jobs:read'), ('automation:jobs:run'), ('automation:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 8. Register Plugin in Master Registry Table
DELETE FROM public.system_plugins WHERE id IN ('automa', 'workflows');

SELECT public.register_plugin(
    'automation',
    'Automation Cloud Bridge',
    '1.0.0',
    'automation',
    ARRAY['runners']::TEXT[],
    'Distributed browser automation coordinator, composite package blocks, batch job executions, and telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
