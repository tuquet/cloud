-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS, QUOTA & PAYMENT GATEWAY (UNINSTALLATION)
-- Plugin ID: subscriptions
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Atomic Schema Drop (Instantly drops all billing tables, views, enums, and functions)
DROP SCHEMA IF EXISTS billing CASCADE;

-- 2. Unregister Plugin from Master Registry (Validates reverse dependencies)
SELECT public.unregister_plugin('subscriptions');

-- 3. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions
WHERE permission_id LIKE 'subscriptions:%'
   OR permission_id LIKE 'quota:%'
   OR permission_id LIKE 'wallets:%'
   OR permission_id LIKE 'payments:%';
DELETE FROM public.permissions WHERE module = 'billing';
