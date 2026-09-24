-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SOFT DELETE & DATA RETENTION PATTERN (UNINSTALLATION SCRIPT)
-- Plugin Name: soft_delete
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL
-- Description: Reverts soft delete RLS policies and helper functions.
-- ============================================================================

-- 1. Drop Helper Functions
DROP FUNCTION IF EXISTS public.hard_delete_project(UUID);
DROP FUNCTION IF EXISTS public.restore_project(UUID);
DROP FUNCTION IF EXISTS public.soft_delete_project(UUID);

-- 2. Restore Standard RLS Policy on Projects
DROP POLICY IF EXISTS "projects_select_trash_tenant_admin" ON public.projects;
DROP POLICY IF EXISTS "projects_select_active_tenant_member" ON public.projects;

DROP POLICY IF EXISTS "projects_select_tenant_member" ON public.projects;
CREATE POLICY "projects_select_tenant_member" ON public.projects
    FOR SELECT TO authenticated
    USING (
        tenant_id IN (SELECT public.get_user_tenant_ids())
        AND (
            public.has_tenant_permission(tenant_id, 'projects:read')
            OR public.is_tenant_admin(tenant_id)
        )
    );

-- 3. Drop Index & Column
DROP INDEX IF EXISTS public.idx_projects_deleted_at;
ALTER TABLE public.projects DROP COLUMN IF EXISTS deleted_at;
