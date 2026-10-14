-- ============================================================================
-- TUQUET-CLOUD PLUGIN: DIGITAL PRODUCTS STORE & AUTO-FULFILLMENT (UNINSTALLATION)
-- Plugin ID: commerce
-- Architecture: Atomic Zero-Orphan Cleanup via DROP SCHEMA CASCADE
-- ============================================================================

-- 1. Remove cross-schema trigger on billing.payment_intents if billing schema exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'billing' AND table_name = 'payment_intents'
    ) THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_commerce_on_payment_intent_settled ON billing.payment_intents';
    END IF;
END $$;

-- 2. Atomic Schema Drop (Instantly drops all commerce tables, enums, and functions)
DROP SCHEMA IF EXISTS commerce CASCADE;

-- 3. Unregister Plugin from Master Registry
SELECT public.unregister_plugin('commerce');

-- 4. Cleanup Permissions from Base Core
DELETE FROM public.role_permissions
WHERE permission_id LIKE 'commerce:%';
DELETE FROM public.permissions WHERE module = 'commerce';
