-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS & QUOTA METERING (UNINSTALLATION SCRIPT)
-- Plugin ID: subscriptions
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Drop Quota Trigger from Core Projects Table
DROP TRIGGER IF EXISTS trigger_enforce_project_quota ON public.projects;

-- 2. Atomic Schema Drop (Instantly drops all billing tables, views, enums, and functions)
DROP SCHEMA IF EXISTS billing CASCADE;

-- 3. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('subscriptions');

-- 4. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'subscriptions:%' OR permission_id LIKE 'quota:%';
DELETE FROM public.permissions WHERE module = 'billing';
