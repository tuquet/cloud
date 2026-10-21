-- ============================================================================
-- TUQUET-CLOUD PLUGIN: CLOUD BROWSER PROFILES (UNINSTALLATION SCRIPT)
-- Plugin ID: browsers
-- ============================================================================

-- 1. Drop Public PostgREST Facades
DROP FUNCTION IF EXISTS public.acquire_browser_profile(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.release_browser_profile(UUID, UUID, TEXT, TEXT, BIGINT, TEXT, INT, JSONB);
DROP FUNCTION IF EXISTS public.reap_stale_browser_locks(INTERVAL);

-- 2. Unregister Plugin from Catalog
SELECT public.unregister_plugin('browsers', TRUE);

-- 3. Revoke permissions and role mappings
DELETE FROM public.role_permissions WHERE permission_id LIKE 'browsers:%';
DELETE FROM public.permissions WHERE module = 'browsers';

-- 4. Clean up Storage Bucket (if exists)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        DELETE FROM storage.buckets WHERE id = 'browser-profiles';
    END IF;
END $$;

-- 5. Drop Schema and Cascading Objects
DROP SCHEMA IF EXISTS browsers CASCADE;
