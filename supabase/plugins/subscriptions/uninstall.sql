-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS, ENTITLEMENTS & QUOTA METERING (UNINSTALLATION SCRIPT)
-- Plugin Name: subscriptions
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL
-- Description: Cleanly drops subscription tiers, quota triggers, functions,
--              tables, and permissions without affecting Base Core.
-- ============================================================================

-- 1. Drop Quota Trigger from Projects
DROP TRIGGER IF EXISTS trigger_enforce_project_quota ON public.projects;
DROP FUNCTION IF EXISTS public.enforce_project_quota();
DROP FUNCTION IF EXISTS public.check_tenant_quota(UUID, TEXT);

-- 2. Drop Triggers on Subscriptions Tables
DROP TRIGGER IF EXISTS update_tenant_subscriptions_modtime ON public.tenant_subscriptions;

-- 3. Drop Tables (In reverse dependency order)
DROP TABLE IF EXISTS public.usage_meters CASCADE;
DROP TABLE IF EXISTS public.tenant_subscriptions CASCADE;
DROP TABLE IF EXISTS public.subscription_plans CASCADE;

-- 4. Drop Enums
DROP TYPE IF EXISTS public.subscription_status CASCADE;

-- 5. Cleanup Permissions
DELETE FROM public.role_permissions WHERE permission_id LIKE 'subscriptions:%' OR permission_id LIKE 'quota:%';
DELETE FROM public.permissions WHERE module = 'billing';
