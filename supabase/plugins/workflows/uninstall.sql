-- ============================================================================
-- TUQUET-CLOUD PLUGIN: WORKFLOWS CLOUD BRIDGE (UNINSTALLATION SCRIPT)
-- Plugin ID: workflows
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Atomic Schema Drop (Instantly drops all tables, types, triggers, views, and functions)
DROP SCHEMA IF EXISTS workflows CASCADE;

-- 2. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('workflows');

-- 3. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'workflows:%';
DELETE FROM public.permissions WHERE module = 'workflows';
