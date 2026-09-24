-- ============================================================================
-- SUPABASE MIGRATION: AUTOMA CLOUD BRIDGE (DISTRIBUTED AUTOMATION ENGINE)
-- Version: 20260924000005
-- Description: Multi-tenant schemas, RLS, and permissions for Tuquet Automa.
--              Includes Workflows, Runners, Campaign Runs, Execution Logs, and Schedules.
-- Note: All tables strictly adhere to the user prefix requirement: automa_*
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

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

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

-- ============================================================================
-- 2. TABLE DEFINITIONS (PREFIX: automa_*)
-- ============================================================================

-- 2.1. Workflows: Định nghĩa quy trình tự động hóa (Visual nodes/edges JSON)
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

COMMENT ON TABLE public.automa_workflows IS 'Workflow flow graphs and visual execution definitions';

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

COMMENT ON TABLE public.automa_runners IS 'Registered distributed Rust runner nodes executing automation tasks';

-- 2.3. Campaign Runs: Các phiên thực thi chiến dịch/quy trình theo lô
CREATE TABLE IF NOT EXISTS public.automa_campaign_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID REFERENCES public.automa_workflows(id) ON DELETE SET NULL,
    runner_id UUID REFERENCES public.automa_runners(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    status public.automa_campaign_status NOT NULL DEFAULT 'pending',
    trigger_type VARCHAR(64) NOT NULL DEFAULT 'manual', -- 'manual', 'schedule', 'webhook', 'api'
    input_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    output_results JSONB NOT NULL DEFAULT '{}'::jsonb,
    total_tasks INT NOT NULL DEFAULT 0 CHECK (total_tasks >= 0),
    completed_tasks INT NOT NULL DEFAULT 0 CHECK (completed_tasks >= 0),
    failed_tasks INT NOT NULL DEFAULT 0 CHECK (failed_tasks >= 0),
    progress_percent NUMERIC(5, 2) NOT NULL DEFAULT 0.00 CHECK (progress_percent >= 0.00 AND progress_percent <= 100.00),
    error_message TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_campaign_runs IS 'Execution instances of automation workflows with real-time status and stats';

-- 2.4. Execution Logs: Nhật ký và telemetry chi tiết của từng bước chạy
CREATE TABLE IF NOT EXISTS public.automa_execution_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    campaign_run_id UUID REFERENCES public.automa_campaign_runs(id) ON DELETE CASCADE,
    runner_id UUID REFERENCES public.automa_runners(id) ON DELETE SET NULL,
    step_name VARCHAR(128),
    level public.automa_log_level NOT NULL DEFAULT 'info',
    message TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_execution_logs IS 'Granular step execution and runner telemetry log stream';

-- 2.5. Schedules: Lập lịch kích hoạt tự động theo Cron
CREATE TABLE IF NOT EXISTS public.automa_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    workflow_id UUID NOT NULL REFERENCES public.automa_workflows(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    cron_expression VARCHAR(64) NOT NULL,
    timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.automa_schedules IS 'Cron-based scheduled triggers for automated workflow execution';

-- ============================================================================
-- 3. CHỈ MỤC HIỆU NĂNG CAO (COMPOSITE INDEXES)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_automa_workflows_tenant_created 
    ON public.automa_workflows (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_workflows_deleted_at 
    ON public.automa_workflows (tenant_id, deleted_at) WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_automa_runners_tenant_status 
    ON public.automa_runners (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_automa_runners_heartbeat 
    ON public.automa_runners (status, last_heartbeat_at);

CREATE INDEX IF NOT EXISTS idx_automa_campaigns_tenant_status 
    ON public.automa_campaign_runs (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_workflow 
    ON public.automa_campaign_runs (workflow_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_campaigns_runner 
    ON public.automa_campaign_runs (runner_id) WHERE runner_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_automa_logs_tenant_campaign 
    ON public.automa_execution_logs (tenant_id, campaign_run_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automa_logs_level 
    ON public.automa_execution_logs (tenant_id, level, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_automa_schedules_tenant_active 
    ON public.automa_schedules (tenant_id, is_active) WHERE is_active = TRUE;

-- ============================================================================
-- 4. DATABASE TRIGGERS (UPDATED_AT & OUTBOX TELEMETRY)
-- ============================================================================

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

-- Trigger to log campaign lifecycle to outbox for webhook dispatching
CREATE OR REPLACE FUNCTION public.log_automa_campaign_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'outbox_events') THEN
        IF (TG_OP = 'INSERT') THEN
            INSERT INTO public.outbox_events (tenant_id, event_type, payload)
            VALUES (
                NEW.tenant_id,
                'automa.campaign.created',
                jsonb_build_object(
                    'campaign_run_id', NEW.id,
                    'name', NEW.name,
                    'workflow_id', NEW.workflow_id,
                    'trigger_type', NEW.trigger_type,
                    'status', NEW.status
                )
            );
        ELSIF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
            INSERT INTO public.outbox_events (tenant_id, event_type, payload)
            VALUES (
                NEW.tenant_id,
                'automa.campaign.status_changed',
                jsonb_build_object(
                    'campaign_run_id', NEW.id,
                    'old_status', OLD.status,
                    'new_status', NEW.status,
                    'progress_percent', NEW.progress_percent,
                    'error_message', NEW.error_message
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_automa_campaign_event ON public.automa_campaign_runs;
CREATE TRIGGER trigger_log_automa_campaign_event
    AFTER INSERT OR UPDATE ON public.automa_campaign_runs
    FOR EACH ROW EXECUTE FUNCTION public.log_automa_campaign_event_to_outbox();

-- ============================================================================
-- 5. PHÂN QUYỀN RBAC (PERMISSIONS & ROLE MAPPINGS)
-- ============================================================================

INSERT INTO public.permissions (id, module, description) VALUES
    ('automa:workflows:read', 'automa', 'Xem danh sách và chi tiết các quy trình Automa'),
    ('automa:workflows:manage', 'automa', 'Tạo, sửa, xuất bản và xóa quy trình Automa'),
    ('automa:runners:read', 'automa', 'Xem danh sách máy trạm (runners) và trạng thái kết nối'),
    ('automa:runners:manage', 'automa', 'Đăng ký, cấu hình và quản lý các node runners'),
    ('automa:campaigns:read', 'automa', 'Xem lịch sử và tiến độ thực thi các chiến dịch Automa'),
    ('automa:campaigns:run', 'automa', 'Kích hoạt, tạm dừng hoặc hủy bỏ phiên chạy chiến dịch'),
    ('automa:campaigns:manage', 'automa', 'Cấu hình tham số chiến dịch và lập lịch tự động'),
    ('automa:logs:read', 'automa', 'Xem nhật ký chi tiết và telemetry thực thi của runners')
ON CONFLICT (id) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

-- Gán toàn quyền Automa cho system role 'owner' và 'admin'
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automa:workflows:read'), ('automa:workflows:manage'),
        ('automa:runners:read'), ('automa:runners:manage'),
        ('automa:campaigns:read'), ('automa:campaigns:run'), ('automa:campaigns:manage'),
        ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Gán quyền thực thi cho system role 'member'
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

-- Gán quyền chỉ đọc cho system role 'viewer'
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES 
        ('automa:workflows:read'),
        ('automa:runners:read'),
        ('automa:campaigns:read'),
        ('automa:logs:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'viewer'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ============================================================================
-- 6. CHÍNH SÁCH BẢO MẬT HÀNG (ROW LEVEL SECURITY - RLS)
-- ============================================================================

ALTER TABLE public.automa_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_runners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_campaign_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_execution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automa_schedules ENABLE ROW LEVEL SECURITY;

-- 6.1. automa_workflows RLS Policies
DROP POLICY IF EXISTS "automa_workflows_select_active" ON public.automa_workflows;
CREATE POLICY "automa_workflows_select_active" ON public.automa_workflows
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:workflows:read')
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS "automa_workflows_select_trash_admin" ON public.automa_workflows;
CREATE POLICY "automa_workflows_select_trash_admin" ON public.automa_workflows
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_admin(tenant_id)
        AND deleted_at IS NOT NULL
    );

DROP POLICY IF EXISTS "automa_workflows_insert" ON public.automa_workflows;
CREATE POLICY "automa_workflows_insert" ON public.automa_workflows
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:workflows:manage')
    );

DROP POLICY IF EXISTS "automa_workflows_update" ON public.automa_workflows;
CREATE POLICY "automa_workflows_update" ON public.automa_workflows
    FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:workflows:manage'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'automa:workflows:manage'));

DROP POLICY IF EXISTS "automa_workflows_delete" ON public.automa_workflows;
CREATE POLICY "automa_workflows_delete" ON public.automa_workflows
    FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:workflows:manage'));

-- 6.2. automa_runners RLS Policies
DROP POLICY IF EXISTS "automa_runners_select" ON public.automa_runners;
CREATE POLICY "automa_runners_select" ON public.automa_runners
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:runners:read')
    );

DROP POLICY IF EXISTS "automa_runners_manage" ON public.automa_runners;
CREATE POLICY "automa_runners_manage" ON public.automa_runners
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:runners:manage'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'automa:runners:manage'));

-- 6.3. automa_campaign_runs RLS Policies
DROP POLICY IF EXISTS "automa_campaigns_select" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_select" ON public.automa_campaign_runs
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:campaigns:read')
    );

DROP POLICY IF EXISTS "automa_campaigns_insert" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_insert" ON public.automa_campaign_runs
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_tenant_member(tenant_id)
        AND (
            public.has_tenant_permission(tenant_id, 'automa:campaigns:run')
            OR public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
        )
    );

DROP POLICY IF EXISTS "automa_campaigns_update" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_update" ON public.automa_campaign_runs
    FOR UPDATE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:run')
        OR public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
    )
    WITH CHECK (
        public.has_tenant_permission(tenant_id, 'automa:campaigns:run')
        OR public.has_tenant_permission(tenant_id, 'automa:campaigns:manage')
    );

DROP POLICY IF EXISTS "automa_campaigns_delete" ON public.automa_campaign_runs;
CREATE POLICY "automa_campaigns_delete" ON public.automa_campaign_runs
    FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:campaigns:manage'));

-- 6.4. automa_execution_logs RLS Policies
DROP POLICY IF EXISTS "automa_logs_select" ON public.automa_execution_logs;
CREATE POLICY "automa_logs_select" ON public.automa_execution_logs
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:logs:read')
    );

DROP POLICY IF EXISTS "automa_logs_insert" ON public.automa_execution_logs;
CREATE POLICY "automa_logs_insert" ON public.automa_execution_logs
    FOR INSERT TO authenticated
    WITH CHECK (public.is_tenant_member(tenant_id));

-- 6.5. automa_schedules RLS Policies
DROP POLICY IF EXISTS "automa_schedules_select" ON public.automa_schedules;
CREATE POLICY "automa_schedules_select" ON public.automa_schedules
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
        AND public.has_tenant_permission(tenant_id, 'automa:campaigns:read')
    );

DROP POLICY IF EXISTS "automa_schedules_manage" ON public.automa_schedules;
CREATE POLICY "automa_schedules_manage" ON public.automa_schedules
    FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'automa:campaigns:manage'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'automa:campaigns:manage'));
