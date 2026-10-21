-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMATION CLOUD BRIDGE (UNINSTALLATION SCRIPT)
-- Plugin ID: automation
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Atomic Schema Drop (Instantly drops all tables, types, triggers, views, and functions)
DROP SCHEMA IF EXISTS automation CASCADE;

-- 2. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('automation');

-- 3. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'automation:%';
DELETE FROM public.permissions WHERE module = 'automation';
