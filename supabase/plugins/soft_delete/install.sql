-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SOFT DELETE & DATA RETENTION PATTERN (INSTALLATION SCRIPT)
-- Plugin Name: soft_delete
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL (Recycle Bin & Data Retention)
-- Description: Adds soft-delete column, views, and trash recovery functions.
-- ============================================================================

-- 1. Add deleted_at column to projects table
ALTER TABLE public.projects 
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN public.projects.deleted_at IS '[Plugin: soft_delete] Timestamp when record was soft-deleted. NULL means active record.';

CREATE INDEX IF NOT EXISTS idx_projects_deleted_at ON public.projects (tenant_id, deleted_at) WHERE deleted_at IS NOT NULL;

-- 2. Update existing RLS Select policy on projects to exclude soft-deleted records by default
DROP POLICY IF EXISTS "projects_select_tenant_member" ON public.projects;
DROP POLICY IF EXISTS "projects_select_active_tenant_member" ON public.projects;

CREATE POLICY "projects_select_active_tenant_member" ON public.projects
    FOR SELECT TO authenticated
    USING (
        tenant_id IN (SELECT public.get_user_tenant_ids())
        AND public.has_tenant_permission(tenant_id, 'projects:read')
        AND deleted_at IS NULL
    );

-- Allow Tenant Admins to view soft-deleted projects in Trash / Archive view
DROP POLICY IF EXISTS "projects_select_trash_tenant_admin" ON public.projects;
CREATE POLICY "projects_select_trash_tenant_admin" ON public.projects
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_admin(tenant_id)
        AND deleted_at IS NOT NULL
    );

-- 3. Soft Delete Helper Functions
CREATE OR REPLACE FUNCTION public.soft_delete_project(_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM public.projects
    WHERE id = _project_id AND deleted_at IS NULL;

    IF v_tenant_id IS NULL THEN
        RETURN FALSE;
    END IF;

    IF NOT (public.has_tenant_permission(v_tenant_id, 'projects:delete') OR public.is_tenant_admin(v_tenant_id)) THEN
        RAISE EXCEPTION 'Permission denied: Cannot soft-delete project'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.projects
    SET deleted_at = timezone('utc'::text, now())
    WHERE id = _project_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_project(_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM public.projects
    WHERE id = _project_id AND deleted_at IS NOT NULL;

    IF v_tenant_id IS NULL THEN
        RETURN FALSE;
    END IF;

    IF NOT public.is_tenant_admin(v_tenant_id) THEN
        RAISE EXCEPTION 'Permission denied: Only tenant admin can restore deleted projects'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.projects
    SET deleted_at = NULL
    WHERE id = _project_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.hard_delete_project(_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM public.projects
    WHERE id = _project_id;

    IF v_tenant_id IS NULL THEN
        RETURN FALSE;
    END IF;

    IF NOT public.is_tenant_admin(v_tenant_id) THEN
        RAISE EXCEPTION 'Permission denied: Only tenant admin can permanently purge projects'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.projects WHERE id = _project_id;
    RETURN TRUE;
END;
$$;
