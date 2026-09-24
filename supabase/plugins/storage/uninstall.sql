-- ============================================================================
-- TUQUET-CLOUD PLUGIN: MEDIA STORAGE & ASSETS MANAGEMENT (UNINSTALLATION SCRIPT)
-- Plugin Name: storage (Media Assets)
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL
-- Description: Cleanly drops media_assets table, triggers, RLS, permissions,
--              and storage bucket policies without affecting Base Core.
-- ============================================================================

-- 1. Drop Storage RLS Policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DROP POLICY IF EXISTS "storage_objects_select_tenant" ON storage.objects;
        DROP POLICY IF EXISTS "storage_objects_insert_tenant" ON storage.objects;
        DROP POLICY IF EXISTS "storage_objects_delete_tenant" ON storage.objects;
    END IF;
END $$;

-- 2. Drop Table RLS Policies & Triggers
DROP POLICY IF EXISTS "media_assets_select_tenant_member" ON public.media_assets;
DROP POLICY IF EXISTS "media_assets_insert_tenant_member" ON public.media_assets;
DROP POLICY IF EXISTS "media_assets_delete_tenant_admin" ON public.media_assets;
DROP TRIGGER IF EXISTS update_media_assets_modtime ON public.media_assets;

-- 3. Drop Table & Indexes
DROP TABLE IF EXISTS public.media_assets CASCADE;

-- 4. Cleanup Permissions Dictionary
DELETE FROM public.role_permissions WHERE permission_id LIKE 'media:%';
DELETE FROM public.permissions WHERE module = 'media';
