-- ============================================================================
-- MODULE: AUTOMA CLOUD BRIDGE (DOWN MIGRATION - SAFE ROLLBACK)
-- Version: 20260924000005
-- Scope: Safely revert and drop all Automa Cloud Bridge schemas, triggers,
--        RLS policies, composite indexes, enums, and permissions.
-- Target: Supabase / PostgreSQL (public schema)
-- Safety: Cascades foreign keys within automa_* domain while preserving tenants,
--         profiles, roles, and unrelated application data.
-- ============================================================================

-- migrate:down

-- ----------------------------------------------------------------------------
-- 1. DROP TRIGGERS & FUNCTIONS
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trigger_log_automa_campaign_event ON public.automa_campaign_runs;
DROP FUNCTION IF EXISTS public.log_automa_campaign_event_to_outbox();

DROP TRIGGER IF EXISTS set_automa_schedules_updated_at ON public.automa_schedules;
DROP TRIGGER IF EXISTS set_automa_campaigns_updated_at ON public.automa_campaign_runs;
DROP TRIGGER IF EXISTS set_automa_runners_updated_at ON public.automa_runners;
DROP TRIGGER IF EXISTS set_automa_workflows_updated_at ON public.automa_workflows;

-- ----------------------------------------------------------------------------
-- 2. DROP ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
-- automa_schedules
DROP POLICY IF EXISTS "automa_schedules_select" ON public.automa_schedules;
DROP POLICY IF EXISTS "automa_schedules_manage" ON public.automa_schedules;

-- automa_execution_logs
DROP POLICY IF EXISTS "automa_logs_select" ON public.automa_execution_logs;
DROP POLICY IF EXISTS "automa_logs_insert" ON public.automa_execution_logs;

-- automa_campaign_runs
DROP POLICY IF EXISTS "automa_campaigns_select" ON public.automa_campaign_runs;
DROP POLICY IF EXISTS "automa_campaigns_insert" ON public.automa_campaign_runs;
DROP POLICY IF EXISTS "automa_campaigns_update" ON public.automa_campaign_runs;
DROP POLICY IF EXISTS "automa_campaigns_delete" ON public.automa_campaign_runs;

-- automa_runners
DROP POLICY IF EXISTS "automa_runners_select" ON public.automa_runners;
DROP POLICY IF EXISTS "automa_runners_manage" ON public.automa_runners;

-- automa_workflows
DROP POLICY IF EXISTS "automa_workflows_select_active" ON public.automa_workflows;
DROP POLICY IF EXISTS "automa_workflows_select_trash_admin" ON public.automa_workflows;
DROP POLICY IF EXISTS "automa_workflows_insert" ON public.automa_workflows;
DROP POLICY IF EXISTS "automa_workflows_update" ON public.automa_workflows;
DROP POLICY IF EXISTS "automa_workflows_delete" ON public.automa_workflows;

-- ----------------------------------------------------------------------------
-- 3. DROP COMPOSITE INDEXES
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_automa_schedules_tenant_active;
DROP INDEX IF EXISTS public.idx_automa_logs_level;
DROP INDEX IF EXISTS public.idx_automa_logs_tenant_campaign;
DROP INDEX IF EXISTS public.idx_automa_campaigns_runner;
DROP INDEX IF EXISTS public.idx_automa_campaigns_workflow;
DROP INDEX IF EXISTS public.idx_automa_campaigns_tenant_status;
DROP INDEX IF EXISTS public.idx_automa_runners_heartbeat;
DROP INDEX IF EXISTS public.idx_automa_runners_tenant_status;
DROP INDEX IF EXISTS public.idx_automa_workflows_deleted_at;
DROP INDEX IF EXISTS public.idx_automa_workflows_tenant_created;

-- ----------------------------------------------------------------------------
-- 4. DROP TABLES (IN REVERSE DEPENDENCY ORDER)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS public.automa_schedules CASCADE;
DROP TABLE IF EXISTS public.automa_execution_logs CASCADE;
DROP TABLE IF EXISTS public.automa_campaign_runs CASCADE;
DROP TABLE IF EXISTS public.automa_runners CASCADE;
DROP TABLE IF EXISTS public.automa_workflows CASCADE;

-- ----------------------------------------------------------------------------
-- 5. DROP ENUMS
-- ----------------------------------------------------------------------------
DROP TYPE IF EXISTS public.automa_log_level CASCADE;
DROP TYPE IF EXISTS public.automa_campaign_status CASCADE;
DROP TYPE IF EXISTS public.automa_runner_status CASCADE;
DROP TYPE IF EXISTS public.automa_workflow_status CASCADE;

-- ----------------------------------------------------------------------------
-- 6. CLEANUP RBAC PERMISSIONS & OUTBOX TELEMETRY
-- ----------------------------------------------------------------------------
-- Revoke all automa permissions assigned to roles
DELETE FROM public.role_permissions 
WHERE permission_id LIKE 'automa:%';

-- Remove atomic automa permissions from permissions catalog
DELETE FROM public.permissions 
WHERE module = 'automa';

-- Remove any pending/historical automa outbox events
DELETE FROM public.outbox_events 
WHERE event_type LIKE 'automa.%';
