-- ============================================================================
-- TUQUET-CLOUD PLUGIN: DEMO PROJECTS RESOURCE (INSTALLATION SCRIPT)
-- Plugin ID: demo-projects
-- Architecture: Domain Resource attached to Core IAM Tenant Boundary
-- ============================================================================

-- 1. Create Projects Table
CREATE TABLE IF NOT EXISTS public.projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.projects IS '[Plugin: demo-projects] Demonstration business resource isolated by tenant boundary';

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_projects_tenant_created ON public.projects(tenant_id, created_at DESC);

-- 3. Trigger for updated_at
DROP TRIGGER IF EXISTS set_projects_updated_at ON public.projects;
CREATE TRIGGER set_projects_updated_at 
    BEFORE UPDATE ON public.projects 
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 4. Row Level Security (RLS)
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant members can view projects" ON public.projects;
CREATE POLICY "Tenant members can view projects"
    ON public.projects FOR SELECT TO authenticated
    USING (
        tenant_id IN (SELECT public.get_user_tenant_ids()) 
        AND (public.has_tenant_permission(tenant_id, 'projects:read') OR public.is_tenant_member(tenant_id))
    );

DROP POLICY IF EXISTS "Tenant members with create permission can insert projects" ON public.projects;
CREATE POLICY "Tenant members with create permission can insert projects"
    ON public.projects FOR INSERT TO authenticated
    WITH CHECK (
        tenant_id IN (SELECT public.get_user_tenant_ids()) 
        AND (public.has_tenant_permission(tenant_id, 'projects:create') OR public.is_tenant_admin(tenant_id))
    );

DROP POLICY IF EXISTS "Tenant members with update permission can edit projects" ON public.projects;
CREATE POLICY "Tenant members with update permission can edit projects"
    ON public.projects FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'projects:update') OR public.is_tenant_admin(tenant_id))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'projects:update') OR public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "Tenant members with delete permission can delete projects" ON public.projects;
CREATE POLICY "Tenant members with delete permission can delete projects"
    ON public.projects FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'projects:delete') OR public.is_tenant_admin(tenant_id));

-- 5. Register Permissions in Core Dictionary
INSERT INTO public.permissions (id, module, description) VALUES
    ('projects:read',   'projects', 'Xem danh sách và chi tiết dự án'),
    ('projects:create', 'projects', 'Tạo dự án mới trong tổ chức'),
    ('projects:update', 'projects', 'Chỉnh sửa nội dung dự án'),
    ('projects:delete', 'projects', 'Xóa bỏ dự án khỏi tổ chức')
ON CONFLICT (id) DO UPDATE SET 
    description = EXCLUDED.description,
    module = EXCLUDED.module;

-- Gán quyền cho Owner & Admin
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (
    VALUES ('projects:read'), ('projects:create'), ('projects:update'), ('projects:delete')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Gán quyền cho Member (đọc, tạo, sửa)
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000003', 'projects:read'),
    ('00000000-0000-0000-0000-000000000003', 'projects:create'),
    ('00000000-0000-0000-0000-000000000003', 'projects:update')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Gán quyền cho Viewer (chỉ đọc)
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000004', 'projects:read')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 6. Register Plugin in Master Registry
SELECT public.register_plugin(
    'demo-projects',
    'Demo Projects Resource',
    '1.0.0',
    'public',
    ARRAY['core-iam']::TEXT[],
    'Showcase domain resource demonstrating multi-tenant foreign keys, RLS scoping, and granular permissions',
    FALSE,
    '{"table": "public.projects", "category": "demo"}'::jsonb
);
