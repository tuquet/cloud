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

-- ============================================================================
-- 4.3. Execution orchestration (SPEC-automation-execution)
--      Queue + scheduler + idempotency + lease. Idempotent DDL: safe to re-run.
-- ============================================================================

-- jobs: provenance, dedupe, lease & retry
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS schedule_id      UUID REFERENCES automation.schedules(id) ON DELETE SET NULL;
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS idempotency_key  TEXT;
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS params_snapshot  JSONB;
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS attempts         INT NOT NULL DEFAULT 0;
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS max_attempts     INT NOT NULL DEFAULT 1;
ALTER TABLE automation.jobs ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ;

-- One (tenant, workflow, key) ⇒ at most one job: the anti-double-run guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS uq_automation_jobs_idempotency
    ON automation.jobs (tenant_id, workflow_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_automation_jobs_queue
    ON automation.jobs (tenant_id, status, created_at)
    WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS idx_automation_jobs_lease
    ON automation.jobs (status, lease_expires_at)
    WHERE status = 'running';
CREATE INDEX IF NOT EXISTS idx_automation_jobs_schedule
    ON automation.jobs (schedule_id, created_at DESC);

-- schedules: input parameters + overlap policy
ALTER TABLE automation.schedules ADD COLUMN IF NOT EXISTS parameters    JSONB   NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE automation.schedules ADD COLUMN IF NOT EXISTS allow_overlap BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_automation_schedules_due
    ON automation.schedules (next_run_at) WHERE is_active;

-- 5. Business Logic Functions & Procedures

-- 5.1. High-Performance Atomic job Claiming (`FOR UPDATE SKIP LOCKED`)
DROP FUNCTION IF EXISTS automation.claim_next_job(UUID, INT);

CREATE OR REPLACE FUNCTION automation.claim_next_job(
    p_worker_id UUID,
    p_batch_size INT DEFAULT 1,
    p_lease INTERVAL DEFAULT INTERVAL '15 minutes'
)
RETURNS SETOF automation.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    -- NOTE: workers.device_status is {offline, idle, busy, maintenance, disabled} — a device
    -- that can take work is `idle` or `busy` (there is no `running` device status).
    SELECT tenant_id INTO v_tenant_id
    FROM workers.devices
    WHERE id = p_worker_id AND status IN ('idle', 'busy');

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
        started_at = COALESCE(r.started_at, timezone('utc'::text, now())),
        attempts = r.attempts + 1,
        lease_expires_at = timezone('utc'::text, now()) + p_lease,
        updated_at = timezone('utc'::text, now())
    FROM candidate_runs c
    WHERE r.id = c.id
    RETURNING r.*;
END;
$$;

-- ============================================================================
-- 5.2. Execution orchestration functions (SPEC-automation-execution)
-- ============================================================================

-- 5.2.1. Cron field matcher: supports `*`, lists `a,b`, ranges `a-b`, steps `*/n`, `a-b/n`.
CREATE OR REPLACE FUNCTION automation.cron_field_matches(
    p_field TEXT,
    p_value INT,
    p_min INT,
    p_max INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_part  TEXT;
    v_range TEXT;
    v_step  INT;
    v_lo    INT;
    v_hi    INT;
BEGIN
    IF p_field IS NULL OR btrim(p_field) IN ('', '*') THEN
        RETURN TRUE;
    END IF;

    FOREACH v_part IN ARRAY string_to_array(p_field, ',') LOOP
        v_part := btrim(v_part);
        IF v_part = '' THEN
            CONTINUE;
        END IF;

        v_step := 1;
        v_range := v_part;
        IF position('/' IN v_part) > 0 THEN
            v_range := split_part(v_part, '/', 1);
            BEGIN
                v_step := split_part(v_part, '/', 2)::INT;
            EXCEPTION WHEN others THEN
                v_step := 1;
            END;
            IF v_step IS NULL OR v_step < 1 THEN
                v_step := 1;
            END IF;
        END IF;

        IF v_range = '*' THEN
            v_lo := p_min;
            v_hi := p_max;
        ELSIF position('-' IN v_range) > 0 THEN
            BEGIN
                v_lo := split_part(v_range, '-', 1)::INT;
                v_hi := split_part(v_range, '-', 2)::INT;
            EXCEPTION WHEN others THEN
                CONTINUE;
            END;
        ELSE
            BEGIN
                v_lo := v_range::INT;
                v_hi := v_lo;
            EXCEPTION WHEN others THEN
                CONTINUE;
            END;
        END IF;

        IF p_value BETWEEN v_lo AND v_hi AND ((p_value - v_lo) % v_step) = 0 THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;

-- 5.2.2. Does a 5-field cron expression match this timestamp? (evaluated in local time)
CREATE OR REPLACE FUNCTION automation.cron_matches(p_expr TEXT, p_ts TIMESTAMPTZ)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_fields TEXT[] := regexp_split_to_array(btrim(p_expr), '\s+');
    v_dow    INT;
BEGIN
    IF p_expr IS NULL OR btrim(p_expr) = '' THEN
        RAISE EXCEPTION 'cron expression is empty';
    END IF;
    IF array_length(v_fields, 1) <> 5 THEN
        RAISE EXCEPTION 'invalid cron expression (expected 5 fields): %', p_expr;
    END IF;

    v_dow := EXTRACT(DOW FROM p_ts)::INT; -- 0 = Sunday

    RETURN automation.cron_field_matches(v_fields[1], EXTRACT(MINUTE FROM p_ts)::INT, 0, 59)
       AND automation.cron_field_matches(v_fields[2], EXTRACT(HOUR   FROM p_ts)::INT, 0, 23)
       AND automation.cron_field_matches(v_fields[3], EXTRACT(DAY    FROM p_ts)::INT, 1, 31)
       AND automation.cron_field_matches(v_fields[4], EXTRACT(MONTH  FROM p_ts)::INT, 1, 12)
       AND (
            automation.cron_field_matches(v_fields[5], v_dow, 0, 6)
            OR (v_dow = 0 AND automation.cron_field_matches(v_fields[5], 7, 0, 7))
       );
END;
$$;

-- 5.2.3. Enqueue a job: parameter merge, idempotency, validation.
CREATE OR REPLACE FUNCTION automation.enqueue_job(
    p_tenant_id       UUID,
    p_workflow_id     UUID,
    p_name            TEXT    DEFAULT NULL,
    p_parameters      JSONB   DEFAULT '{}'::jsonb,
    p_schedule_id     UUID    DEFAULT NULL,
    p_idempotency_key TEXT    DEFAULT NULL,
    p_triggered_by    UUID    DEFAULT NULL,
    p_max_attempts    INT     DEFAULT 1
)
RETURNS automation.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_wf       automation.workflows;
    v_defaults JSONB := '{}'::jsonb;
    v_schedule JSONB := '{}'::jsonb;
    v_merged   JSONB;
    v_job      automation.jobs;
BEGIN
    SELECT * INTO v_wf
    FROM automation.workflows
    WHERE id = p_workflow_id AND tenant_id = p_tenant_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'workflow_not_found: % (tenant %)', p_workflow_id, p_tenant_id;
    END IF;
    IF v_wf.status <> 'published' THEN
        RAISE EXCEPTION 'workflow_not_published: % is %', p_workflow_id, v_wf.status;
    END IF;

    -- (1) declared contract: document-root `trigger`, else the trigger block
    SELECT COALESCE(jsonb_object_agg(p ->> 'name', p -> 'defaultValue'), '{}'::jsonb)
    INTO v_defaults
    FROM jsonb_array_elements(
             COALESCE(
                 v_wf.graph_data -> 'trigger' -> 'parameters',
                 (SELECT n -> 'data' -> 'parameters'
                  FROM jsonb_array_elements(COALESCE(v_wf.graph_data -> 'nodes', '[]'::jsonb)) n
                  WHERE n ->> 'label' = 'trigger'
                  LIMIT 1),
                 (SELECT n -> 'data' -> 'parameters'
                  FROM jsonb_array_elements(COALESCE(v_wf.graph_data -> 'drawflow' -> 'nodes', '[]'::jsonb)) n
                  WHERE n ->> 'label' = 'trigger'
                  LIMIT 1),
                 '[]'::jsonb
             )
         ) p
    WHERE (p ? 'name') AND (p ? 'defaultValue') AND p -> 'defaultValue' <> 'null'::jsonb;

    -- (2) schedule-scoped overrides
    IF p_schedule_id IS NOT NULL THEN
        SELECT parameters INTO v_schedule FROM automation.schedules WHERE id = p_schedule_id;
        v_schedule := COALESCE(v_schedule, '{}'::jsonb);
    END IF;

    -- (3) run-scoped overrides
    v_merged := COALESCE(v_defaults, '{}'::jsonb) || v_schedule || COALESCE(p_parameters, '{}'::jsonb);

    -- Idempotency: an existing job with the same key wins, no duplicate is created.
    IF p_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_job
        FROM automation.jobs
        WHERE tenant_id = p_tenant_id
          AND workflow_id = p_workflow_id
          AND idempotency_key = p_idempotency_key;
        IF FOUND THEN
            RETURN v_job;
        END IF;
    END IF;

    INSERT INTO automation.jobs (
        tenant_id, workflow_id, name, status, parameters, params_snapshot,
        schedule_id, idempotency_key, triggered_by, max_attempts
    ) VALUES (
        p_tenant_id,
        p_workflow_id,
        COALESCE(
            NULLIF(btrim(COALESCE(p_name, '')), ''),
            v_wf.name || ' · ' || to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI')
        ),
        'queued',
        v_merged,
        v_merged,
        p_schedule_id,
        p_idempotency_key,
        p_triggered_by,
        GREATEST(COALESCE(p_max_attempts, 1), 1)
    )
    ON CONFLICT DO NOTHING
    RETURNING * INTO v_job;

    IF v_job.id IS NULL AND p_idempotency_key IS NOT NULL THEN
        -- Lost a race against a concurrent enqueue with the same key.
        SELECT * INTO v_job
        FROM automation.jobs
        WHERE tenant_id = p_tenant_id
          AND workflow_id = p_workflow_id
          AND idempotency_key = p_idempotency_key;
    END IF;

    RETURN v_job;
END;
$$;

-- 5.2.4. Scheduler tick: run once a minute; one job per schedule slot.
CREATE OR REPLACE FUNCTION automation.tick_schedules(p_now TIMESTAMPTZ DEFAULT now())
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_schedule RECORD;
    v_local    TIMESTAMP;
    v_slot     TIMESTAMPTZ := date_trunc('minute', p_now);
    v_key      TEXT;
    v_busy     BOOLEAN;
    v_job      automation.jobs;
    v_created  INT := 0;
BEGIN
    FOR v_schedule IN
        SELECT *
        FROM automation.schedules
        WHERE is_active
          AND (next_run_at IS NULL OR next_run_at <= p_now)
        ORDER BY created_at
        FOR UPDATE SKIP LOCKED
    LOOP
        v_local := p_now AT TIME ZONE v_schedule.timezone;

        IF NOT automation.cron_matches(v_schedule.cron_expression, v_local) THEN
            UPDATE automation.schedules
               SET next_run_at = p_now + INTERVAL '1 minute',
                   updated_at  = timezone('utc', now())
             WHERE id = v_schedule.id;
            CONTINUE;
        END IF;

        -- Overlap policy: never stack runs of a schedule that opted out of overlap.
        IF NOT v_schedule.allow_overlap THEN
            SELECT EXISTS (
                SELECT 1 FROM automation.jobs
                WHERE schedule_id = v_schedule.id AND status IN ('queued', 'running')
            ) INTO v_busy;

            IF v_busy THEN
                UPDATE automation.schedules
                   SET last_run_at = p_now,
                       next_run_at = p_now + INTERVAL '1 minute',
                       updated_at  = timezone('utc', now())
                 WHERE id = v_schedule.id;
                CONTINUE;
            END IF;
        END IF;

        v_key := format(
            'schedule:%s:%s',
            v_schedule.id,
            to_char(v_slot AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        );

        v_job := automation.enqueue_job(
            p_tenant_id       => v_schedule.tenant_id,
            p_workflow_id     => v_schedule.workflow_id,
            p_name            => v_schedule.name,
            p_parameters      => v_schedule.parameters,
            p_schedule_id     => v_schedule.id,
            p_idempotency_key => v_key,
            p_triggered_by    => v_schedule.created_by
        );
        v_created := v_created + 1;

        UPDATE automation.schedules
           SET last_run_at = p_now,
               next_run_at = p_now + INTERVAL '1 minute',
               updated_at  = timezone('utc', now())
         WHERE id = v_schedule.id;
    END LOOP;

    RETURN v_created;
END;
$$;

-- 5.2.5. Worker reports the outcome of a claimed job.
CREATE OR REPLACE FUNCTION automation.finish_job(
    p_job_id        UUID,
    p_status        TEXT,
    p_result_summary JSONB DEFAULT '{}'::jsonb,
    p_error_message TEXT  DEFAULT NULL
)
RETURNS automation.jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_job automation.jobs;
BEGIN
    IF p_status NOT IN ('completed', 'failed', 'cancelled') THEN
        RAISE EXCEPTION 'invalid terminal status: %', p_status;
    END IF;

    UPDATE automation.jobs
       SET status          = p_status::automation.job_status,
           result_summary  = COALESCE(p_result_summary, '{}'::jsonb),
           error_message   = p_error_message,
           ended_at        = timezone('utc', now()),
           lease_expires_at = NULL,
           updated_at      = timezone('utc', now())
     WHERE id = p_job_id
       AND status IN ('running', 'queued', 'pending')
    RETURNING * INTO v_job;

    IF v_job.id IS NULL THEN
        -- Already finished (retry/replay): return the stored row, do not clobber it.
        SELECT * INTO v_job FROM automation.jobs WHERE id = p_job_id;
    END IF;

    RETURN v_job;
END;
$$;

-- 5.2.6. Batch-append step logs (tenant is derived from the job, never trusted from caller).
CREATE OR REPLACE FUNCTION automation.log_job_events(p_job_id UUID, p_events JSONB)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant_id UUID;
    v_count     INT := 0;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM automation.jobs WHERE id = p_job_id;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'job_not_found: %', p_job_id;
    END IF;

    INSERT INTO automation.execution_logs (tenant_id, job_id, node_id, step_name, level, message, payload, logged_at)
    SELECT
        v_tenant_id,
        p_job_id,
        NULLIF(e ->> 'node_id', ''),
        NULLIF(e ->> 'step_name', ''),
        CASE
            WHEN e ->> 'level' IN ('trace', 'debug', 'info', 'warn', 'error', 'fatal')
                THEN (e ->> 'level')::automation.log_level
            ELSE 'info'::automation.log_level
        END,
        COALESCE(e ->> 'message', ''),
        COALESCE(e -> 'payload', '{}'::jsonb),
        COALESCE((e ->> 'logged_at')::TIMESTAMPTZ, timezone('utc', now()))
    FROM jsonb_array_elements(COALESCE(p_events, '[]'::jsonb)) e;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- 5.2.7. Renew the lease of a running job (called on every worker heartbeat).
CREATE OR REPLACE FUNCTION automation.renew_job_lease(
    p_job_id UUID,
    p_lease  INTERVAL DEFAULT INTERVAL '15 minutes'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
BEGIN
    UPDATE automation.jobs
       SET lease_expires_at = timezone('utc', now()) + p_lease,
           updated_at       = timezone('utc', now())
     WHERE id = p_job_id AND status = 'running';

    RETURN FOUND;
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
    v_requeued INT := 0;
    v_failed   INT := 0;
BEGIN
    -- A running job is stale when its worker stopped heart-beating OR its lease expired.
    -- Retry while attempts remain; otherwise fail it for good (SPEC-automation-execution §9).
    WITH stale AS (
        SELECT r.id, r.attempts, r.max_attempts
        FROM automation.jobs r
        LEFT JOIN workers.devices d ON d.id = r.worker_id
        WHERE r.status = 'running'
          AND (
                r.lease_expires_at < timezone('utc'::text, now())
             OR d.id IS NULL
             OR d.status = 'offline'
             OR d.last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
          )
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE automation.jobs r
       SET status           = 'queued',
           worker_id        = NULL,
           lease_expires_at = NULL,
           error_message    = format('Lease expired after attempt %s/%s — requeued', r.attempts, r.max_attempts),
           updated_at       = timezone('utc'::text, now())
      FROM stale s
     WHERE r.id = s.id AND s.attempts < s.max_attempts;
    GET DIAGNOSTICS v_requeued = ROW_COUNT;

    WITH stale AS (
        SELECT r.id, r.attempts, r.max_attempts
        FROM automation.jobs r
        LEFT JOIN workers.devices d ON d.id = r.worker_id
        WHERE r.status = 'running'
          AND (
                r.lease_expires_at < timezone('utc'::text, now())
             OR d.id IS NULL
             OR d.status = 'offline'
             OR d.last_heartbeat_at < (timezone('utc'::text, now()) - p_stale_interval)
          )
        FOR UPDATE OF r SKIP LOCKED
    )
    UPDATE automation.jobs r
       SET status           = 'failed',
           lease_expires_at = NULL,
           error_message    = 'Worker node heartbeat timed out (Dead Lease Reaper)',
           ended_at         = timezone('utc'::text, now()),
           updated_at       = timezone('utc'::text, now())
      FROM stale s
     WHERE r.id = s.id AND s.attempts >= s.max_attempts;
    GET DIAGNOSTICS v_failed = ROW_COUNT;

    RETURN v_requeued + v_failed;
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

-- 7.1. Execution orchestration grants (SPEC-automation-execution)
GRANT EXECUTE ON FUNCTION automation.cron_field_matches(TEXT, INT, INT, INT) TO service_role;
GRANT EXECUTE ON FUNCTION automation.cron_matches(TEXT, TIMESTAMPTZ) TO service_role;
GRANT EXECUTE ON FUNCTION automation.enqueue_job(UUID, UUID, TEXT, JSONB, UUID, TEXT, UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION automation.tick_schedules(TIMESTAMPTZ) TO service_role;
GRANT EXECUTE ON FUNCTION automation.finish_job(UUID, TEXT, JSONB, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION automation.log_job_events(UUID, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION automation.renew_job_lease(UUID, INTERVAL) TO service_role;
GRANT EXECUTE ON FUNCTION automation.claim_next_job(UUID, INT, INTERVAL) TO service_role;
GRANT EXECUTE ON FUNCTION automation.reap_stale_jobs(INTERVAL) TO service_role;

-- 7.2. Scheduler wiring: tick + reaper every minute (no-op where pg_cron is unavailable).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('tuquet_automation_tick', '* * * * *', $cron$SELECT automation.tick_schedules()$cron$);
        PERFORM cron.schedule('tuquet_automation_reap', '* * * * *', $cron$SELECT automation.reap_stale_jobs()$cron$);
        RAISE NOTICE 'pg_cron: automation tick + reap scheduled';
    ELSE
        RAISE NOTICE 'pg_cron not installed — automation tick/reap not scheduled';
    END IF;
END $$;

-- ============================================================================
-- 7.3. Worker-facing RPC wrappers (public schema) — SPEC-automation-execution §14
--      `automation` is not exposed through PostgREST, so the worker calls these.
--      Every call is authenticated by the device token (same scheme as the secrets plugin).
-- ============================================================================

CREATE OR REPLACE FUNCTION automation._verify_device(p_device_id UUID, p_device_token TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workers, public, extensions, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_hash   TEXT;
BEGIN
    IF p_device_id IS NULL OR p_device_token IS NULL OR p_device_token = '' THEN
        RAISE EXCEPTION 'Device credentials required';
    END IF;
    v_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');
    SELECT tenant_id INTO v_tenant
    FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_hash;
    IF v_tenant IS NULL THEN
        RAISE EXCEPTION 'Invalid or unknown device credentials';
    END IF;
    RETURN v_tenant;
END;
$$;

-- Claim a batch of queued jobs, each with the workflow document the engine needs.
CREATE OR REPLACE FUNCTION public.automation_claim_jobs(
    p_device_id    UUID,
    p_device_token TEXT,
    p_batch_size   INT      DEFAULT 1,
    p_lease        INTERVAL DEFAULT INTERVAL '15 minutes'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_result JSONB;
BEGIN
    v_tenant := automation._verify_device(p_device_id, p_device_token);

    IF NOT EXISTS (
        SELECT 1 FROM workers.devices
        WHERE id = p_device_id AND status IN ('idle', 'busy')
    ) THEN
        RAISE EXCEPTION 'device_not_available: % cannot take work in its current status', p_device_id;
    END IF;

    SELECT COALESCE(jsonb_agg(envelope ORDER BY claimed.created_at), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT r.*, w.graph_data AS wf_graph, w.name AS wf_name, w.version AS wf_version
        FROM automation.claim_next_job(p_device_id, GREATEST(COALESCE(p_batch_size, 1), 1), p_lease) r
        JOIN automation.workflows w ON w.id = r.workflow_id
    ) claimed
    CROSS JOIN LATERAL (
        SELECT jsonb_build_object(
            'job_id',        claimed.id,
            'workflow_id',   claimed.workflow_id,
            'workflow_name', claimed.wf_name,
            'workflow_version', claimed.wf_version,
            'name',          claimed.name,
            'parameters',    claimed.parameters,
            'attempts',      claimed.attempts,
            'max_attempts',  claimed.max_attempts,
            'lease_expires_at', claimed.lease_expires_at,
            'document',      claimed.wf_graph
        ) AS envelope
    ) e;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.automation_finish_job(
    p_device_id     UUID,
    p_device_token  TEXT,
    p_job_id        UUID,
    p_status        TEXT,
    p_result_summary JSONB DEFAULT '{}'::jsonb,
    p_error_message TEXT  DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant UUID;
BEGIN
    v_tenant := automation._verify_device(p_device_id, p_device_token);

    IF NOT EXISTS (
        SELECT 1 FROM automation.jobs
        WHERE id = p_job_id AND tenant_id = v_tenant AND worker_id = p_device_id
    ) THEN
        RAISE EXCEPTION 'job_not_owned_by_device: %', p_job_id;
    END IF;

    PERFORM automation.finish_job(p_job_id, p_status, p_result_summary, p_error_message);
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.automation_renew_job_lease(
    p_device_id    UUID,
    p_device_token TEXT,
    p_job_id       UUID,
    p_lease        INTERVAL DEFAULT INTERVAL '15 minutes'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant UUID;
BEGIN
    v_tenant := automation._verify_device(p_device_id, p_device_token);

    IF NOT EXISTS (
        SELECT 1 FROM automation.jobs
        WHERE id = p_job_id AND tenant_id = v_tenant AND worker_id = p_device_id AND status = 'running'
    ) THEN
        RAISE EXCEPTION 'job_not_owned_by_device: %', p_job_id;
    END IF;

    RETURN automation.renew_job_lease(p_job_id, p_lease);
END;
$$;

CREATE OR REPLACE FUNCTION public.automation_log_job_events(
    p_device_id    UUID,
    p_device_token TEXT,
    p_job_id       UUID,
    p_events       JSONB
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = automation, public, pg_temp
AS $$
DECLARE
    v_tenant UUID;
BEGIN
    v_tenant := automation._verify_device(p_device_id, p_device_token);

    IF NOT EXISTS (
        SELECT 1 FROM automation.jobs
        WHERE id = p_job_id AND tenant_id = v_tenant AND worker_id = p_device_id
    ) THEN
        RAISE EXCEPTION 'job_not_owned_by_device: %', p_job_id;
    END IF;

    RETURN automation.log_job_events(p_job_id, p_events);
END;
$$;

GRANT EXECUTE ON FUNCTION public.automation_claim_jobs(UUID, TEXT, INT, INTERVAL) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.automation_finish_job(UUID, TEXT, UUID, TEXT, JSONB, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.automation_renew_job_lease(UUID, TEXT, UUID, INTERVAL) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.automation_log_job_events(UUID, TEXT, UUID, JSONB) TO authenticated, service_role;

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
