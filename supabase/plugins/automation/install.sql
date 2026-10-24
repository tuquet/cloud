-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMATION CLOUD BRIDGE (INSTALLATION SCRIPT)
-- Plugin ID: automation
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: automation)
-- Dependencies: ["workers"]
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

-- 3.3. jobs (Consumes Compute Node from schema workers)
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
-- Doctrine (2026-10-24): `workflows.variables` was a dead duplicate of the trigger's declared
-- parameters. Dropped — the workflow's input contract lives in graph_data.trigger.data.parameters.
ALTER TABLE automation.workflows DROP COLUMN IF EXISTS variables;
DROP INDEX IF EXISTS automation.idx_automation_workflows_vars_gin;

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
        RAISE EXCEPTION 'Worker % is invalid or offline', p_worker_id;
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
SET search_path = automation, workers, public, pg_temp
AS $$
DECLARE
    v_reaped_count INT := 0;
BEGIN
    WITH dead_workers AS (
        SELECT id, tenant_id
        FROM workers.devices
        WHERE last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
           OR status = 'offline'
    ),
    stale_runs AS (
        SELECT r.id
        FROM automation.jobs r
        JOIN dead_workers d ON r.worker_id = d.id AND r.tenant_id = d.tenant_id
        WHERE r.status = 'running'
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE automation.jobs r
    SET 
        status = 'failed',
        error_message = 'Worker node heartbeat timed out (Dead Lease Reaper)',
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


-- ============================================================================
-- 7.5. Workflow RPCs — supported read/write path for the workstation CLI/console
--      PostgREST only exposes the `public` schema, so these wrappers are the
--      contract into `automation.workflows`. SECURITY INVOKER keeps RLS in force
--      (`is_tenant_member(tenant_id)` for reads, `automation:workflows:manage`
--      or tenant admin for writes).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.workflow_list(p_search TEXT DEFAULT NULL)
RETURNS SETOF automation.workflows
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $$
    SELECT w.*
    FROM automation.workflows w
    WHERE w.deleted_at IS NULL
      AND (
        p_search IS NULL OR btrim(p_search) = ''
        OR w.name ILIKE '%' || p_search || '%'
        OR coalesce(w.description, '') ILIKE '%' || p_search || '%'
      )
    ORDER BY w.updated_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.workflow_get(p_target TEXT)
RETURNS SETOF automation.workflows
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $$
    SELECT w.*
    FROM automation.workflows w
    WHERE w.deleted_at IS NULL
      AND (w.id::text = p_target OR w.name = p_target)
    LIMIT 1;
$$;

-- Publish-time validation (Automa-schema doctrine): **declared => satisfied**.
-- A workflow is only persisted when the contract the canvas declares can actually be
-- honoured headlessly. See tasks/hrms-automation-workflow.md §0.3.
CREATE OR REPLACE FUNCTION automation.validate_workflow_graph(p_graph JSONB)
RETURNS void
LANGUAGE plpgsql IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_node  JSONB;
    v_param JSONB;
    v_name  TEXT;
    v_seen  TEXT[] := ARRAY[]::TEXT[];
    v_match TEXT[];
BEGIN
    IF p_graph IS NULL OR jsonb_typeof(p_graph) <> 'object' THEN
        RETURN;
    END IF;

    -- (1)+(2) trigger.data.parameters[] = the declared input contract (authored on the canvas)
    IF jsonb_typeof(p_graph -> 'nodes') = 'array' THEN
        FOR v_node IN SELECT value FROM jsonb_array_elements(p_graph -> 'nodes')
        LOOP
            IF coalesce(v_node ->> 'label', v_node ->> 'type', '') <> 'trigger' THEN
                CONTINUE;
            END IF;
            IF jsonb_typeof(v_node -> 'data' -> 'parameters') <> 'array' THEN
                CONTINUE;
            END IF;
            FOR v_param IN SELECT value FROM jsonb_array_elements(v_node -> 'data' -> 'parameters')
            LOOP
                v_name := nullif(btrim(coalesce(v_param ->> 'name', '')), '');
                IF v_name IS NULL THEN
                    RAISE EXCEPTION 'workflow rejected: trigger parameter without a name';
                END IF;
                IF NOT (v_param ? 'defaultValue') OR v_param -> 'defaultValue' = 'null'::jsonb THEN
                    RAISE EXCEPTION 'workflow rejected: trigger parameter "%" declares no defaultValue — a headless run would silently have no value (declared => satisfied)', v_name;
                END IF;
                IF v_name = ANY (v_seen) THEN
                    RAISE EXCEPTION 'workflow rejected: duplicate trigger parameter "%"', v_name;
                END IF;
                v_seen := v_seen || v_name;
            END LOOP;
        END LOOP;
    END IF;

    -- (3) no plaintext credential parked under a credential-looking key.
    -- Scanned on the serialized graph (PostgreSQL forbids the recursive self-reference
    -- inside a LATERAL subquery, so a regex sweep is both simpler and sufficient).
    FOR v_match IN
        SELECT regexp_matches(
            p_graph::text,
            '"(password|passwd|pwd|secret|token|api_key|apikey)"\s*:\s*"([^"]+)"',
            'gi'
        )
    LOOP
        IF position('{{secrets@' IN v_match[2]) = 0 THEN
            RAISE EXCEPTION
                'workflow rejected: plaintext credential under key "%" — reference it as {{secrets@name}} instead',
                v_match[1];
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.workflow_upsert(
    p_tenant UUID,
    p_target TEXT DEFAULT NULL,
    p_name TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_version TEXT DEFAULT '1.0.0',
    p_graph_data JSONB DEFAULT '{}'::jsonb,
    p_settings JSONB DEFAULT '{}'::jsonb
) RETURNS SETOF automation.workflows
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    v_id UUID;
BEGIN
    -- Publish-time validation: the canvas contract must be satisfiable headlessly.
    IF p_graph_data IS NOT NULL THEN
        PERFORM automation.validate_workflow_graph(p_graph_data);
    END IF;

    IF p_target IS NOT NULL AND btrim(p_target) <> '' THEN
        SELECT w.id INTO v_id FROM automation.workflows w
        WHERE w.deleted_at IS NULL AND (w.id::text = p_target OR w.name = p_target)
        LIMIT 1;
    END IF;

    IF v_id IS NULL AND p_name IS NOT NULL AND btrim(p_name) <> '' THEN
        SELECT w.id INTO v_id FROM automation.workflows w
        WHERE w.deleted_at IS NULL AND w.name = p_name
        LIMIT 1;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO automation.workflows (tenant_id, name, description, version, graph_data, settings, created_by)
        VALUES (p_tenant, p_name, p_description, p_version, p_graph_data, p_settings, auth.uid())
        RETURNING id INTO v_id;
    ELSE
        UPDATE automation.workflows
        SET name = coalesce(p_name, name),
            description = coalesce(p_description, description),
            version = coalesce(p_version, version),
            graph_data = coalesce(p_graph_data, graph_data),
            settings = coalesce(p_settings, settings),
            updated_at = timezone('utc', now())
        WHERE id = v_id;
    END IF;

    RETURN QUERY SELECT w.* FROM automation.workflows w WHERE w.id = v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.workflow_delete(p_target TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT w.id INTO v_id FROM automation.workflows w
    WHERE w.deleted_at IS NULL AND (w.id::text = p_target OR w.name = p_target)
    LIMIT 1;

    IF v_id IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE automation.workflows SET deleted_at = timezone('utc', now()) WHERE id = v_id;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.workflow_list(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_get(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_upsert(UUID, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION automation.validate_workflow_graph(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_delete(TEXT) TO authenticated;

-- 8. Register Plugin in Master Registry Table
DELETE FROM public.system_plugins WHERE id IN ('automation', 'workflows');

SELECT public.register_plugin(
    'automation',
    'Automation Cloud Bridge',
    '1.0.0',
    'automation',
    ARRAY['workers']::TEXT[],
    'Distributed browser automation coordinator, composite package blocks, batch job executions, and telemetry',
    FALSE,
    '{"author": "Tuquet Team", "license": "MIT"}'::jsonb
);
