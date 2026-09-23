-- ============================================================================
-- MODULE 1: MEDIA STORAGE & ASSETS MANAGEMENT
-- Description: Multi-tenant Media Assets table and Supabase Storage RLS policies.
-- Usage: Execute in Supabase SQL Editor or append to migrations when media capability is needed.
-- ============================================================================

-- Helper function for updated_at column timestamp refresh
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- 1. Create Media Assets Metadata Table
CREATE TABLE IF NOT EXISTS public.media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE SET NULL,
    file_path TEXT NOT NULL,
    bucket_name TEXT NOT NULL DEFAULT 'tenant-assets',
    original_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Comments & Indexing
COMMENT ON TABLE public.media_assets IS 'Stores metadata for tenant files uploaded to Supabase Storage';

CREATE INDEX IF NOT EXISTS idx_media_assets_tenant_created ON public.media_assets (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_media_assets_project_id ON public.media_assets (project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_media_assets_file_path ON public.media_assets (bucket_name, file_path);

-- Trigger for updated_at
CREATE OR REPLACE TRIGGER update_media_assets_modtime
    BEFORE UPDATE ON public.media_assets
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Enable RLS
ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;

-- Add Permissions to Master Seed if not present
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('media:read', 'media', 'View and download tenant media assets'),
    ('media:upload', 'media', 'Upload new media assets to tenant storage'),
    ('media:delete', 'media', 'Delete media assets from tenant storage')
ON CONFLICT (id) DO NOTHING;

-- Assign permissions to system 'owner' and 'admin' roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES ('media:read'), ('media:upload'), ('media:delete')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Assign 'media:read' to system 'member' role
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, 'media:read'
FROM public.roles r
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- RLS Policies for media_assets table
DROP POLICY IF EXISTS "media_assets_select_tenant_member" ON public.media_assets;
CREATE POLICY "media_assets_select_tenant_member" ON public.media_assets
    FOR SELECT TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'media:read')
        OR public.is_tenant_member(tenant_id)
    );

DROP POLICY IF EXISTS "media_assets_insert_tenant_member" ON public.media_assets;
CREATE POLICY "media_assets_insert_tenant_member" ON public.media_assets
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_tenant_permission(tenant_id, 'media:upload')
    );

DROP POLICY IF EXISTS "media_assets_delete_tenant_admin" ON public.media_assets;
CREATE POLICY "media_assets_delete_tenant_admin" ON public.media_assets
    FOR DELETE TO authenticated
    USING (
        public.has_tenant_permission(tenant_id, 'media:delete')
    );

-- 2. Supabase Storage Bucket & RLS Setup
-- Create 'tenant-assets' bucket if storage schema exists
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'tenant-assets',
    'tenant-assets',
    FALSE,
    52428800, -- 50MB Limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf', 'video/mp4']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage Objects RLS: Tenant Isolation via path structure: 'tenant_id/...'
-- Path convention: <tenant_id>/<project_id>/<filename>

DROP POLICY IF EXISTS "storage_objects_select_tenant" ON storage.objects;
CREATE POLICY "storage_objects_select_tenant" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'tenant-assets'
        AND (storage.foldername(name))[1]::uuid IN (
            SELECT public.get_user_tenant_ids()
        )
    );

DROP POLICY IF EXISTS "storage_objects_insert_tenant" ON storage.objects;
CREATE POLICY "storage_objects_insert_tenant" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'tenant-assets'
        AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:upload')
    );

DROP POLICY IF EXISTS "storage_objects_delete_tenant" ON storage.objects;
CREATE POLICY "storage_objects_delete_tenant" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'tenant-assets'
        AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:delete')
    );
