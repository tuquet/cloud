-- ============================================================================
-- TUQUET-CLOUD PLUGIN: DEMO PROJECTS RESOURCE (UNINSTALLATION SCRIPT)
-- Plugin ID: demo-projects
-- Architecture: Atomic Cleanup of Projects Resource
-- ============================================================================

-- 1. Drop Table and dependent constraints
DROP TABLE IF EXISTS public.projects CASCADE;

-- 2. Unregister Plugin from Master Registry
SELECT public.unregister_plugin('demo-projects');

-- 3. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'projects:%';
DELETE FROM public.permissions WHERE module = 'projects';
