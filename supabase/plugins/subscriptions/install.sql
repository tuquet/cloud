-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS & QUOTA METERING (INSTALLATION SCRIPT)
-- Plugin ID: subscriptions
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: billing)
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS billing;
GRANT USAGE ON SCHEMA billing TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA billing GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA billing GRANT ALL ON FUNCTIONS TO authenticated, service_role;

-- 2. Enums & Tables in schema billing
DO $$ BEGIN
    CREATE TYPE billing.subscription_status AS ENUM ('free_tier', 'trialing', 'active', 'past_due', 'canceled', 'unpaid');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS billing.plans (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    max_members INT NOT NULL DEFAULT 5,
    max_storage_mb BIGINT NOT NULL DEFAULT 500,
    max_monthly_runs INT NOT NULL DEFAULT 1000,
    price_monthly_usd NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.plans IS '[Plugin: subscriptions] SaaS subscription tiers defining resource limits and pricing';

CREATE TABLE IF NOT EXISTS billing.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL REFERENCES billing.plans(id) ON DELETE RESTRICT,
    status billing.subscription_status NOT NULL DEFAULT 'free_tier',
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    current_period_end TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + INTERVAL '100 years'),
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE billing.subscriptions IS '[Plugin: subscriptions] Active tenant subscription mapping to a billing plan';

CREATE TABLE IF NOT EXISTS billing.usage_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    metric_name VARCHAR(64) NOT NULL,
    current_value BIGINT NOT NULL DEFAULT 0,
    reset_at TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_billing_tenant_metric UNIQUE (tenant_id, metric_name)
);

COMMENT ON TABLE billing.usage_meters IS '[Plugin: subscriptions] Generic usage counters tracked per tenant and metric';

-- 3. Seed Default Plans
INSERT INTO billing.plans (id, name, description, max_members, max_storage_mb, max_monthly_runs, price_monthly_usd)
VALUES 
    ('free', 'Free Starter', 'Entry plan for personal creators and small tests', 2, 500, 1000, 0.00),
    ('pro', 'Creator Pro', 'Advanced automation capabilities with team collaboration', 10, 10240, 50000, 29.00),
    ('enterprise', 'Enterprise Fleet', 'Dedicated runners, custom quotas, and SLAs', 100, 102400, 1000000, 199.00)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    max_members = EXCLUDED.max_members,
    max_storage_mb = EXCLUDED.max_storage_mb,
    max_monthly_runs = EXCLUDED.max_monthly_runs;

-- 4. Generic Quota Checking & Usage Recording Functions
CREATE OR REPLACE FUNCTION billing.check_tenant_quota(
    _tenant_id UUID, 
    _metric_name TEXT, 
    _increment BIGINT DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_plan_id TEXT;
    v_max_members INT;
    v_max_storage_mb BIGINT;
    v_max_monthly_runs INT;
    v_current_count BIGINT;
BEGIN
    SELECT s.plan_id INTO v_plan_id
    FROM billing.subscriptions s
    WHERE s.tenant_id = _tenant_id AND s.status IN ('free_tier', 'trialing', 'active')
    LIMIT 1;

    IF v_plan_id IS NULL THEN v_plan_id := 'free'; END IF;

    SELECT max_members, max_storage_mb, max_monthly_runs 
    INTO v_max_members, v_max_storage_mb, v_max_monthly_runs
    FROM billing.plans WHERE id = v_plan_id;

    IF _metric_name = 'members' THEN
        SELECT COUNT(*) INTO v_current_count FROM public.tenant_members WHERE tenant_id = _tenant_id AND status = 'active';
        RETURN (v_current_count + _increment) <= v_max_members;
    ELSIF _metric_name = 'monthly_runs' THEN
        SELECT COALESCE(current_value, 0) INTO v_current_count FROM billing.usage_meters WHERE tenant_id = _tenant_id AND metric_name = 'monthly_runs';
        RETURN (v_current_count + _increment) <= v_max_monthly_runs;
    ELSIF _metric_name = 'storage_mb' THEN
        SELECT COALESCE(current_value, 0) INTO v_current_count FROM billing.usage_meters WHERE tenant_id = _tenant_id AND metric_name = 'storage_mb';
        RETURN (v_current_count + _increment) <= v_max_storage_mb;
    END IF;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION billing.record_usage(
    _tenant_id UUID,
    _metric_name TEXT,
    _increment BIGINT DEFAULT 1
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_new_val BIGINT;
BEGIN
    INSERT INTO billing.usage_meters (tenant_id, metric_name, current_value, updated_at)
    VALUES (_tenant_id, _metric_name, _increment, timezone('utc'::text, now()))
    ON CONFLICT (tenant_id, metric_name) DO UPDATE SET
        current_value = billing.usage_meters.current_value + _increment,
        updated_at = timezone('utc'::text, now())
    RETURNING current_value INTO v_new_val;

    RETURN v_new_val;
END;
$$;

-- 5. RLS
ALTER TABLE billing.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.usage_meters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plans_select" ON billing.plans FOR SELECT TO authenticated USING (is_active = TRUE);
CREATE POLICY "subscriptions_select" ON billing.subscriptions FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));
CREATE POLICY "meters_select" ON billing.usage_meters FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

-- 6. Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('subscriptions:read',   'billing', 'View subscription plans and current tenant status'),
    ('subscriptions:manage', 'billing', 'Upgrade, downgrade, or cancel tenant subscription'),
    ('quota:read',           'billing', 'View usage meters and limits')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES ('subscriptions:read'), ('subscriptions:manage'), ('quota:read')) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES ('subscriptions:read'), ('quota:read')) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 7. Register Plugin in Master Registry
SELECT public.register_plugin(
    'subscriptions',
    'Subscriptions & Quota Metering',
    '1.0.0',
    'billing',
    ARRAY[]::TEXT[],
    'SaaS Subscription Tiers, Tenant Subscription state, Usage Metering, and Quota Rules',
    FALSE,
    '{"default_currency": "USD"}'::jsonb
);
