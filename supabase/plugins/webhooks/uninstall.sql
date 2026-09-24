-- ============================================================================
-- TUQUET-CLOUD PLUGIN: ASYNCHRONOUS OUTBOX & WEBHOOKS QUEUE (UNINSTALLATION SCRIPT)
-- Plugin Name: webhooks (Transactional Outbox)
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL
-- Description: Cleanly drops outbox queue, webhooks, triggers, and permissions.
-- ============================================================================

-- 1. Drop Project Event Trigger
DROP TRIGGER IF EXISTS trigger_log_project_outbox ON public.projects;
DROP FUNCTION IF EXISTS public.log_project_event_to_outbox();

-- 2. Drop Triggers on Webhook Subscriptions
DROP TRIGGER IF EXISTS update_webhook_subscriptions_modtime ON public.webhook_subscriptions;

-- 3. Drop Tables (In reverse dependency order)
DROP TABLE IF EXISTS public.webhook_deliveries CASCADE;
DROP TABLE IF EXISTS public.webhook_subscriptions CASCADE;
DROP TABLE IF EXISTS public.outbox_events CASCADE;

-- 4. Drop Enum
DROP TYPE IF EXISTS public.outbox_status CASCADE;

-- 5. Cleanup Permissions
DELETE FROM public.role_permissions WHERE permission_id LIKE 'webhooks:%' OR permission_id LIKE 'outbox:%';
DELETE FROM public.permissions WHERE module = 'integrations';
