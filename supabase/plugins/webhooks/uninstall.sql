-- ============================================================================
-- TUQUET-CLOUD PLUGIN: TRANSACTIONAL OUTBOX & WEBHOOKS (UNINSTALLATION SCRIPT)
-- Plugin ID: webhooks
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Drop Outbox Trigger from Core Members Table
DROP TRIGGER IF EXISTS trigger_log_member_outbox ON public.tenant_members;

-- 2. Atomic Schema Drop (Instantly drops all events tables, views, enums, and functions)
DROP SCHEMA IF EXISTS events CASCADE;

-- 3. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('webhooks');

-- 4. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions WHERE permission_id LIKE 'webhooks:%' OR permission_id LIKE 'outbox:%';
DELETE FROM public.permissions WHERE module = 'integrations';
