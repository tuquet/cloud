-- ============================================================================
-- TUQUET-CLOUD PLUGIN: SUBSCRIPTIONS, ENTITLEMENTS & QUOTA METERING (INSTALLATION SCRIPT)
-- Plugin Name: subscriptions
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL (Billing & Quotas)
-- Description: SaaS Tiers, Quota Enforcement (max projects, max members), & Usage Tracking.
-- ============================================================================

-- Helper function for updated_at column timestamp refresh if not already defined
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- 1. Enums
DO $$ BEGIN
    CREATE TYPE public.subscription_status AS ENUM (
        'free_tier',
        'trialing',
        'active',
        'past_due',
        'canceled',
        'unpaid'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Subscription Plans Table
CREATE TABLE IF NOT EXISTS public.subscription_plans (
    id TEXT PRIMARY KEY, -- e.g. 'free', 'pro', 'enterprise'
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

COMMENT ON TABLE public.subscription_plans IS '[Plugin: subscriptions] Catalog of available SaaS subscription tiers and feature limits';

-- 3. Tenant Subscriptions Table
CREATE TABLE IF NOT EXISTS public.tenant_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL REFERENCES public.subscription_plans(id) ON DELETE RESTRICT,
    status public.subscription_status NOT NULL DEFAULT 'free_tier',
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    current_period_end TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + INTERVAL '100 years'), -- default perpetual free
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.tenant_subscriptions IS '[Plugin: subscriptions] Active subscription tier and billing state per tenant';

CREATE INDEX IF NOT EXISTS idx_tenant_subscriptions_tenant ON public.tenant_subscriptions (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_subscriptions_status ON public.tenant_subscriptions (status);

-- 4. Usage Meters Table
CREATE TABLE IF NOT EXISTS public.usage_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    metric_name VARCHAR(64) NOT NULL, -- e.g. 'api_requests', 'storage_bytes'
    current_value BIGINT NOT NULL DEFAULT 0,
    reset_at TIMESTAMPTZ NOT NULL DEFAULT (date_trunc('month', timezone('utc'::text, now())) + INTERVAL '1 month'),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_tenant_metric UNIQUE (tenant_id, metric_name)
);

COMMENT ON TABLE public.usage_meters IS '[Plugin: subscriptions] Usage metering counters for rate limiting and billing';

CREATE INDEX IF NOT EXISTS idx_usage_meters_tenant ON public.usage_meters (tenant_id);

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_tenant_subscriptions_modtime ON public.tenant_subscriptions;
CREATE TRIGGER update_tenant_subscriptions_modtime
    BEFORE UPDATE ON public.tenant_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 5. Seed Core Subscription Tiers
INSERT INTO public.subscription_plans (id, name, description, max_members, max_projects, max_storage_mb, price_monthly_usd)
VALUES 
    ('free', 'Free Starter', 'Entry plan for personal creators and small tests', 2, 3, 500, 0.00),
    ('pro', 'Creator Pro', 'Advanced automation capabilities with team collaboration', 10, 25, 10240, 29.00),
    ('enterprise', 'Enterprise Fleet', 'Dedicated runners, custom quotas, and SLAs', 100, 500, 102400, 199.00)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    max_members = EXCLUDED.max_members,
    max_projects = EXCLUDED.max_projects,
    max_storage_mb = EXCLUDED.max_storage_mb,
    price_monthly_usd = EXCLUDED.price_monthly_usd;

-- 6. Quota Enforcement Logic (SECURITY DEFINER Function)
CREATE OR REPLACE FUNCTION public.check_tenant_quota(_tenant_id UUID, _feature_key TEXT)
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
    SELECT ts.plan_id INTO v_plan_id
    FROM public.tenant_subscriptions ts
    WHERE ts.tenant_id = _tenant_id AND ts.status IN ('free_tier', 'trialing', 'active')
    LIMIT 1;

    IF v_plan_id IS NULL THEN
        v_plan_id := 'free';
    END IF;

    SELECT max_projects, max_members INTO v_max_projects, v_max_members
    FROM public.subscription_plans
    WHERE id = v_plan_id;

    IF _feature_key = 'projects' THEN
        SELECT COUNT(*) INTO v_current_count
        FROM public.projects
        WHERE tenant_id = _tenant_id;

        RETURN v_current_count < v_max_projects;
    ELSIF _feature_key = 'members' THEN
        SELECT COUNT(*) INTO v_current_count
        FROM public.tenant_members
        WHERE tenant_id = _tenant_id AND status = 'active';

        RETURN v_current_count < v_max_members;
    END IF;

    RETURN TRUE;
END;
$$;

-- 7. Trigger to Enforce Project Quota Limit on INSERT
CREATE OR REPLACE FUNCTION public.enforce_project_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.check_tenant_quota(NEW.tenant_id, 'projects') THEN
        RAISE EXCEPTION 'Tenant quota exceeded: Cannot create more projects under current subscription plan.'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enforce_project_quota ON public.projects;
CREATE TRIGGER trigger_enforce_project_quota
    BEFORE INSERT ON public.projects
    FOR EACH ROW EXECUTE FUNCTION public.enforce_project_quota();

-- 8. RLS Policies
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_meters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscription_plans_select_all" ON public.subscription_plans
    FOR SELECT TO authenticated USING (is_active = TRUE);

CREATE POLICY "tenant_subscriptions_select" ON public.tenant_subscriptions
    FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

CREATE POLICY "usage_meters_select" ON public.usage_meters
    FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));

-- 9. Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('subscriptions:read', 'billing', 'View subscription plans and current tenant subscription'),
    ('subscriptions:manage', 'billing', 'Upgrade, downgrade, or cancel tenant subscription'),
    ('quota:read', 'billing', 'View tenant usage meters and quota limits')
ON CONFLICT (id) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES ('subscriptions:read'), ('subscriptions:manage'), ('quota:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES ('subscriptions:read'), ('quota:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;
