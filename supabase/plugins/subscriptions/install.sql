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
    max_projects INT NOT NULL DEFAULT 3,
    max_storage_mb BIGINT NOT NULL DEFAULT 500,
    price_monthly_usd NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

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

CREATE TABLE IF NOT EXISTS billing.usage_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    metric_name VARCHAR(64) NOT NULL,
    current_value BIGINT NOT NULL DEFAULT 0,
    reset_at TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_billing_tenant_metric UNIQUE (tenant_id, metric_name)
);

-- Seed Default Plans
INSERT INTO billing.plans (id, name, description, max_members, max_projects, max_storage_mb, price_monthly_usd)
VALUES 
    ('free', 'Free Starter', 'Entry plan for personal creators and small tests', 2, 3, 500, 0.00),
    ('pro', 'Creator Pro', 'Advanced automation capabilities with team collaboration', 10, 25, 10240, 29.00),
    ('enterprise', 'Enterprise Fleet', 'Dedicated runners, custom quotas, and SLAs', 100, 500, 102400, 199.00)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, max_members = EXCLUDED.max_members, max_projects = EXCLUDED.max_projects;

-- 3. Quota Enforcement Logic
CREATE OR REPLACE FUNCTION billing.check_tenant_quota(_tenant_id UUID, _feature_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_plan_id TEXT;
    v_max_projects INT;
    v_max_members INT;
    v_current_count BIGINT;
BEGIN
    SELECT s.plan_id INTO v_plan_id
    FROM billing.subscriptions s
    WHERE s.tenant_id = _tenant_id AND s.status IN ('free_tier', 'trialing', 'active')
    LIMIT 1;

    IF v_plan_id IS NULL THEN v_plan_id := 'free'; END IF;

    SELECT max_projects, max_members INTO v_max_projects, v_max_members
    FROM billing.plans WHERE id = v_plan_id;

    IF _feature_key = 'projects' THEN
        SELECT COUNT(*) INTO v_current_count FROM public.projects WHERE tenant_id = _tenant_id;
        RETURN v_current_count < v_max_projects;
    ELSIF _feature_key = 'members' THEN
        SELECT COUNT(*) INTO v_current_count FROM public.tenant_members WHERE tenant_id = _tenant_id AND status = 'active';
        RETURN v_current_count < v_max_members;
    END IF;
    RETURN TRUE;
END;
$$;

-- 4. Trigger on Core Projects
CREATE OR REPLACE FUNCTION billing.enforce_project_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT billing.check_tenant_quota(NEW.tenant_id, 'projects') THEN
        RAISE EXCEPTION 'Tenant quota exceeded: Cannot create more projects under current subscription plan.'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enforce_project_quota ON public.projects;
CREATE TRIGGER trigger_enforce_project_quota
    BEFORE INSERT ON public.projects
    FOR EACH ROW EXECUTE FUNCTION billing.enforce_project_quota();

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
    'SaaS Subscription Tiers, Tenant Subscription state, Usage Metering, and Quota Triggers',
    '{"default_currency": "USD"}'::jsonb
);
