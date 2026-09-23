-- ============================================================================
-- MODULE 4: SOFT DELETE & DATA RETENTION PATTERN
-- Description: Standardized Soft Delete pattern with automatic RLS filtering and recovery functions.
-- Usage: Execute in Supabase SQL Editor or append to migrations when soft delete is required.
-- ============================================================================

-- 1. Add deleted_at column to projects table (as active example)
ALTER TABLE public.projects 
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN public.projects.deleted_at IS 'Timestamp when record was soft-deleted. NULL means active record.';

CREATE INDEX IF NOT EXISTS idx_projects_deleted_at ON public.projects (tenant_id, deleted_at) WHERE deleted_at IS NOT NULL;

-- 2. Update existing RLS Select policy on projects to exclude soft-deleted records by default
DROP POLICY IF EXISTS "projects_select_tenant_member" ON public.projects;

CREATE POLICY "projects_select_active_tenant_member" ON public.projects
    FOR SELECT TO authenticated
    USING (
        public.is_tenant_member(tenant_id)
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
    -- Get project tenant_id
    SELECT tenant_id INTO v_tenant_id
    FROM public.projects
    WHERE id = _project_id AND deleted_at IS NULL;

    IF v_tenant_id IS NULL THEN
        RETURN FALSE; -- Project not found or already deleted
    END IF;

    -- Verify permission (Requires project:delete permission or admin)
    IF NOT (public.has_tenant_permission(v_tenant_id, 'projects:delete') OR public.is_tenant_admin(v_tenant_id)) THEN
        RAISE EXCEPTION 'Permission denied: Cannot soft-delete project'
            USING ERRCODE = '42501';
    END IF;

    -- Perform soft delete
    UPDATE public.projects
    SET deleted_at = timezone('utc'::text, now())
    WHERE id = _project_id;

    RETURN TRUE;
END;
$$;

-- 4. Restore Soft-Deleted Record Function
CREATE OR REPLACE FUNCTION public.restore_project(_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_tenant_id UUID;
BEGIN
    -- Get project tenant_id
    SELECT tenant_id INTO v_tenant_id
    FROM public.projects
    WHERE id = _project_id AND deleted_at IS NOT NULL;

    IF v_tenant_id IS NULL THEN
        RETURN FALSE; -- Project not found in trash
    END IF;

    -- Verify admin permission
    IF NOT public.is_tenant_admin(v_tenant_id) THEN
        RAISE EXCEPTION 'Permission denied: Only Tenant Admins can restore soft-deleted projects'
            USING ERRCODE = '42501';
    END IF;

    -- Perform restore
    UPDATE public.projects
    SET deleted_at = NULL
    WHERE id = _project_id;

    RETURN TRUE;
END;
$$;

-- 5. Hard Delete (Permanent Purge) Function for Retention Policies
CREATE OR REPLACE FUNCTION public.purge_expired_soft_deleted_projects(_retention_days INT DEFAULT 90)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_purged_count BIGINT;
BEGIN
    DELETE FROM public.projects
    WHERE deleted_at IS NOT NULL
      AND deleted_at < (timezone('utc'::text, now()) - (_retention_days || ' days')::INTERVAL);

    GET DIAGNOSTICS v_purged_count = ROW_COUNT;
    RETURN v_purged_count;
END;
$$;
