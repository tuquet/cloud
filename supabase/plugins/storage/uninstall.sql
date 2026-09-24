-- ============================================================================
-- TUQUET-CLOUD PLUGIN: MEDIA STORAGE & ASSETS MANAGEMENT (UNINSTALLATION SCRIPT)
-- Plugin ID: storage
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
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

-- 2. Atomic Schema Drop (Drops media.assets, indexes, views, and functions)
DROP SCHEMA IF EXISTS media CASCADE;

-- 3. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('storage');

-- 4. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'media:%';
DELETE FROM public.permissions WHERE module = 'media';
