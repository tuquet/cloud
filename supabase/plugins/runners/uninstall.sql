-- ============================================================================
-- TUQUET-CLOUD PLUGIN: RUNNERS & COMPUTE FLEET (UNINSTALLATION SCRIPT)
-- Plugin ID: runners
-- ============================================================================

-- 1. Unregister Plugin from Catalog
SELECT public.unregister_plugin('runners', TRUE);

-- 2. Revoke permissions from roles
DELETE FROM public.role_permissions WHERE permission_id LIKE 'runners:%';
DELETE FROM public.permissions WHERE module = 'runners';

-- 3. Drop Schema and Cascading Objects
DROP SCHEMA IF EXISTS runners CASCADE;
