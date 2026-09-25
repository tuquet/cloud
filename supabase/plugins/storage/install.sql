-- ============================================================================
-- TUQUET-CLOUD PLUGIN: MEDIA STORAGE & ASSETS MANAGEMENT (INSTALLATION SCRIPT)
-- Plugin ID: storage
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: media)
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS media;
GRANT USAGE ON SCHEMA media TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA media GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA media GRANT ALL ON FUNCTIONS TO authenticated, service_role;

-- 2. Metadata Table inside schema media
CREATE TABLE IF NOT EXISTS media.assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    project_id UUID DEFAULT NULL,
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

COMMENT ON TABLE media.assets IS '[Plugin: storage] Metadata catalog for tenant assets stored in Supabase Storage';

CREATE INDEX IF NOT EXISTS idx_storage_assets_tenant ON media.assets (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_storage_assets_file_path ON media.assets (bucket_name, file_path);

-- RLS
ALTER TABLE media.assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "assets_select" ON media.assets
    FOR SELECT TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'media:read') OR public.is_tenant_member(tenant_id));

CREATE POLICY "assets_insert" ON media.assets
    FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'media:upload') OR public.is_tenant_admin(tenant_id));

CREATE POLICY "assets_delete" ON media.assets
    FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'media:delete') OR public.is_tenant_admin(tenant_id));

-- 3. Supabase Storage Bucket & Object Policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES ('tenant-assets', 'tenant-assets', FALSE, 52428800, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf', 'video/mp4'])
        ON CONFLICT (id) DO NOTHING;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DROP POLICY IF EXISTS "storage_objects_select_tenant" ON storage.objects;
        CREATE POLICY "storage_objects_select_tenant" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id = 'tenant-assets' AND (storage.foldername(name))[1]::uuid IN (SELECT public.get_user_tenant_ids()));

        DROP POLICY IF EXISTS "storage_objects_insert_tenant" ON storage.objects;
        CREATE POLICY "storage_objects_insert_tenant" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:upload'));

        DROP POLICY IF EXISTS "storage_objects_delete_tenant" ON storage.objects;
        CREATE POLICY "storage_objects_delete_tenant" ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:delete'));
    END IF;
END $$;

-- 4. Register Permissions into Base Core Dictionary
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('media:read',   'media', 'View and download tenant media assets'),
    ('media:upload', 'media', 'Upload new media assets to tenant storage'),
    ('media:delete', 'media', 'Delete media assets from tenant storage')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES ('media:read'), ('media:upload'), ('media:delete')) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, 'media:read' FROM public.roles r
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 5. Register Plugin in Master Registry
SELECT public.register_plugin(
    'storage',
    'Media Storage & Assets',
    '1.0.0',
    'media',
    ARRAY[]::TEXT[],
    'Multi-tenant file metadata management and isolated Supabase Storage bucket RLS policies',
    FALSE,
    '{"bucket": "tenant-assets", "max_file_size_mb": 50}'::jsonb
);
