-- ============================================================================
-- SUPABASE MIGRATION: SUBSCRIPTIONS, ENTITLEMENTS & QUOTA METERING
-- Version: 20260924000002
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

COMMENT ON TABLE public.subscription_plans IS 'Catalog of available SaaS subscription tiers and feature limits';

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

CREATE INDEX IF NOT EXISTS idx_tenant_subscriptions_tenant ON public.tenant_subscriptions (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_subscriptions_status ON public.tenant_subscriptions (status);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_tenant_subscriptions_modtime ON public.tenant_subscriptions;
CREATE TRIGGER update_tenant_subscriptions_modtime
    BEFORE UPDATE ON public.tenant_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 4. Tenant Usage Meters Table
CREATE TABLE IF NOT EXISTS public.tenant_usage_meters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    feature_key TEXT NOT NULL, -- e.g. 'projects_count', 'members_count', 'storage_bytes'
    current_usage BIGINT NOT NULL DEFAULT 0 CHECK (current_usage >= 0),
    last_reset_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_tenant_feature UNIQUE (tenant_id, feature_key)
);

CREATE INDEX IF NOT EXISTS idx_tenant_usage_tenant_feature ON public.tenant_usage_meters (tenant_id, feature_key);

-- Enable RLS
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_usage_meters ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "plans_select_all" ON public.subscription_plans;
CREATE POLICY "plans_select_all" ON public.subscription_plans
    FOR SELECT TO authenticated, anon USING (is_active = TRUE);

DROP POLICY IF EXISTS "tenant_subscriptions_select_member" ON public.tenant_subscriptions;
CREATE POLICY "tenant_subscriptions_select_member" ON public.tenant_subscriptions
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "tenant_usage_select_member" ON public.tenant_usage_meters;
CREATE POLICY "tenant_usage_select_member" ON public.tenant_usage_meters
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

-- 5. Seed Default Subscription Plans
INSERT INTO public.subscription_plans (id, name, description, max_members, max_projects, max_storage_mb, price_monthly_usd)
VALUES
    ('free', 'Free Creator', 'Perfect for individuals and small projects', 3, 5, 500, 0.00),
    ('pro', 'Pro Creator', 'For growing teams requiring higher limits', 20, 50, 10240, 29.00),
    ('enterprise', 'Enterprise Scale', 'Unlimited scale and custom support', 1000, 10000, 1024000, 199.00)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    max_members = EXCLUDED.max_members,
    max_projects = EXCLUDED.max_projects,
    max_storage_mb = EXCLUDED.max_storage_mb,
    price_monthly_usd = EXCLUDED.price_monthly_usd;

-- Auto-assign 'free' plan when a new Tenant is created
CREATE OR REPLACE FUNCTION public.auto_assign_free_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.tenant_subscriptions (tenant_id, plan_id, status)
    VALUES (NEW.id, 'free', 'free_tier')
    ON CONFLICT (tenant_id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_auto_assign_free_subscription ON public.tenants;
CREATE TRIGGER trigger_auto_assign_free_subscription
    AFTER INSERT ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.auto_assign_free_subscription();

-- Backfill existing tenants with free subscription
INSERT INTO public.tenant_subscriptions (tenant_id, plan_id, status)
SELECT t.id, 'free', 'free_tier'
FROM public.tenants t
ON CONFLICT (tenant_id) DO NOTHING;

-- 6. Quota Checking Helper Function
CREATE OR REPLACE FUNCTION public.check_tenant_quota(
    _tenant_id UUID,
    _feature_key TEXT
)
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
    -- Get active plan for tenant (default to free if missing)
    SELECT ts.plan_id INTO v_plan_id
    FROM public.tenant_subscriptions ts
    WHERE ts.tenant_id = _tenant_id AND ts.status IN ('free_tier', 'trialing', 'active')
    LIMIT 1;

    IF v_plan_id IS NULL THEN
        v_plan_id := 'free';
    END IF;

    -- Fetch plan limits
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
