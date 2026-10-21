-- ============================================================================
-- TUQUET-CLOUD PLUGIN: workers & COMPUTE FLEET (UNINSTALLATION SCRIPT)
-- Plugin ID: workers
-- ============================================================================

-- 1. Drop Public PostgREST Facades
DROP FUNCTION IF EXISTS public.heartbeat(UUID, TEXT, INT, JSONB);
DROP FUNCTION IF EXISTS public.acquire_browser(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.release_browser(UUID, UUID, TEXT, TEXT, BIGINT, TEXT, INT, JSONB);
DROP FUNCTION IF EXISTS public.create_browser(VARCHAR, BIGINT, VARCHAR, VARCHAR, UUID, TEXT, TEXT, TEXT, INT, INT, UUID);
DROP FUNCTION IF EXISTS public.list_browsers(UUID, TEXT);
DROP FUNCTION IF EXISTS public.reap_stale_browser_locks(INTERVAL);

-- 2. Unregister Plugin from Catalog
SELECT public.unregister_plugin('workers', TRUE);

-- 3. Revoke permissions and role mappings
DELETE FROM public.role_permissions WHERE permission_id LIKE 'workers:%';
DELETE FROM public.permissions WHERE module = 'workers';

-- 4. Clean up Storage Bucket (if exists)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'buckets') THEN
        DELETE FROM storage.buckets WHERE id = 'browser-profiles';
    END IF;
END $$;

-- 5. Drop Schema and Cascading Objects
DROP SCHEMA IF EXISTS workers CASCADE;
