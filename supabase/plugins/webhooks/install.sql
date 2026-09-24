-- ============================================================================
-- TUQUET-CLOUD PLUGIN: ASYNCHRONOUS OUTBOX & WEBHOOKS QUEUE (INSTALLATION SCRIPT)
-- Plugin Name: webhooks (Transactional Outbox)
-- Version: 1.0.0
-- Target: Supabase / PostgreSQL (Event Dispatching)
-- Description: Transactional Outbox pattern & Outbound Webhook Subscriptions.
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

-- 1. Enum
DO $$ BEGIN
    CREATE TYPE public.outbox_status AS ENUM (
        'pending',
        'processing',
        'delivered',
        'failed'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Outbox Events Table
CREATE TABLE IF NOT EXISTS public.outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status public.outbox_status NOT NULL DEFAULT 'pending',
    retry_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processed_at TIMESTAMPTZ
);

COMMENT ON TABLE public.outbox_events IS '[Plugin: webhooks] Transactional event outbox for reliable async processing and webhook dispatching';

CREATE INDEX IF NOT EXISTS idx_outbox_events_status_created ON public.outbox_events (status, created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_outbox_events_tenant ON public.outbox_events (tenant_id) WHERE tenant_id IS NOT NULL;

-- 3. Webhook Subscriptions Table
CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    target_url TEXT NOT NULL,
    secret TEXT NOT NULL,
    event_types TEXT[] NOT NULL DEFAULT ARRAY['*'],
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.webhook_subscriptions IS '[Plugin: webhooks] Outbound webhook endpoints registered by tenants';

CREATE INDEX IF NOT EXISTS idx_webhook_subscriptions_tenant ON public.webhook_subscriptions (tenant_id) WHERE is_active = TRUE;

-- 4. Webhook Deliveries Table
CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.outbox_events(id) ON DELETE CASCADE,
    status_code INT,
    response_body TEXT,
    duration_ms INT,
    attempt INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.webhook_deliveries IS '[Plugin: webhooks] Audit trail of webhook HTTP dispatch attempts and responses';

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_tenant ON public.webhook_deliveries (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_subscription ON public.webhook_deliveries (subscription_id);

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_webhook_subscriptions_modtime ON public.webhook_subscriptions;
CREATE TRIGGER update_webhook_subscriptions_modtime
    BEFORE UPDATE ON public.webhook_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 5. Automatic Outbox Trigger Example (On Project Changes)
CREATE OR REPLACE FUNCTION public.log_project_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.outbox_events (tenant_id, event_type, payload)
        VALUES (
            NEW.tenant_id,
            'project.created',
            jsonb_build_object(
                'id', NEW.id,
                'name', NEW.name,
                'created_by', NEW.created_by,
                'created_at', NEW.created_at
            )
        );
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO public.outbox_events (tenant_id, event_type, payload)
        VALUES (
            OLD.tenant_id,
            'project.deleted',
            jsonb_build_object(
                'id', OLD.id,
                'name', OLD.name
            )
        );
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_project_outbox ON public.projects;
CREATE TRIGGER trigger_log_project_outbox
    AFTER INSERT OR DELETE ON public.projects
    FOR EACH ROW EXECUTE FUNCTION public.log_project_event_to_outbox();

-- 6. RLS Policies
ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "outbox_events_select_admin" ON public.outbox_events
    FOR SELECT TO authenticated
    USING (
        tenant_id IS NOT NULL 
        AND public.is_tenant_admin(tenant_id)
    );

CREATE POLICY "webhook_subscriptions_all_admin" ON public.webhook_subscriptions
    FOR ALL TO authenticated
    USING (public.is_tenant_admin(tenant_id));

CREATE POLICY "webhook_deliveries_select_admin" ON public.webhook_deliveries
    FOR SELECT TO authenticated
    USING (public.is_tenant_admin(tenant_id));

-- 7. Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('webhooks:manage', 'integrations', 'Create, update, and delete outgoing webhook endpoints'),
    ('outbox:read', 'integrations', 'Inspect background outbox event stream and delivery status')
ON CONFLICT (id) DO UPDATE SET
    module = EXCLUDED.module,
    description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN (
    VALUES ('webhooks:manage'), ('outbox:read')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;
