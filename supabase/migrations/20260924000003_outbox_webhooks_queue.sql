-- ============================================================================
-- SUPABASE MIGRATION: ASYNCHRONOUS OUTBOX & WEBHOOKS QUEUE
-- Version: 20260924000003
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
    event_type TEXT NOT NULL, -- e.g. 'project.created', 'project.deleted', 'tenant.member_invited'
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status public.outbox_status NOT NULL DEFAULT 'pending',
    retry_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processed_at TIMESTAMPTZ
);

COMMENT ON TABLE public.outbox_events IS 'Transactional event outbox for reliable async processing and webhook dispatching';

CREATE INDEX IF NOT EXISTS idx_outbox_events_status_created ON public.outbox_events (status, created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_outbox_events_tenant ON public.outbox_events (tenant_id) WHERE tenant_id IS NOT NULL;

-- 3. Webhook Subscriptions Table
CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    target_url TEXT NOT NULL,
    secret TEXT NOT NULL, -- HMAC signature key
    event_types TEXT[] NOT NULL DEFAULT ARRAY['*'], -- e.g. ARRAY['project.created', 'project.deleted']
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_webhook_subscriptions_tenant ON public.webhook_subscriptions (tenant_id) WHERE is_active = TRUE;

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_webhook_subscriptions_modtime ON public.webhook_subscriptions;
CREATE TRIGGER update_webhook_subscriptions_modtime
    BEFORE UPDATE ON public.webhook_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 4. Webhook Deliveries Table (Audit log for webhooks)
CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id UUID NOT NULL REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.outbox_events(id) ON DELETE CASCADE,
    response_status INT,
    response_body TEXT,
    duration_ms INT,
    status public.outbox_status NOT NULL DEFAULT 'pending',
    delivered_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook ON public.webhook_deliveries (webhook_id, delivered_at DESC);

-- Enable RLS
ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "outbox_events_select_admin" ON public.outbox_events;
CREATE POLICY "outbox_events_select_admin" ON public.outbox_events
    FOR SELECT TO authenticated
    USING (public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "webhooks_all_tenant_admin" ON public.webhook_subscriptions;
CREATE POLICY "webhooks_all_tenant_admin" ON public.webhook_subscriptions
    FOR ALL TO authenticated
    USING (public.is_tenant_admin(tenant_id))
    WITH CHECK (public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "deliveries_select_tenant_admin" ON public.webhook_deliveries;
CREATE POLICY "deliveries_select_tenant_admin" ON public.webhook_deliveries
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.webhook_subscriptions ws
            WHERE ws.id = webhook_id AND public.is_tenant_admin(ws.tenant_id)
        )
    );

-- 5. Automated Event Logging Triggers
-- Example: Automatically log project creation/deletion events to outbox
CREATE OR REPLACE FUNCTION public.log_project_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.outbox_events (tenant_id, event_type, payload)
        VALUES (
            NEW.tenant_id,
            'project.created',
            jsonb_build_object(
                'project_id', NEW.id,
                'name', NEW.name,
                'created_by', NEW.created_by,
                'created_at', NEW.created_at
            )
        );
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO public.outbox_events (tenant_id, event_type, payload)
        VALUES (
            OLD.tenant_id,
            'project.deleted',
            jsonb_build_object(
                'project_id', OLD.id,
                'name', OLD.name
            )
        );
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_project_event ON public.projects;
CREATE TRIGGER trigger_log_project_event
    AFTER INSERT OR DELETE ON public.projects
    FOR EACH ROW EXECUTE FUNCTION public.log_project_event_to_outbox();

-- Example: Automatically log tenant invitations to outbox (for sending emails)
CREATE OR REPLACE FUNCTION public.log_invitation_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.outbox_events (tenant_id, event_type, payload)
    VALUES (
        NEW.tenant_id,
        'tenant.member_invited',
        jsonb_build_object(
            'invitation_id', NEW.id,
            'email', NEW.email,
            'role_id', NEW.role_id,
            'invited_by', NEW.invited_by,
            'expires_at', NEW.expires_at
        )
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_invitation_event ON public.tenant_invitations;
CREATE TRIGGER trigger_log_invitation_event
    AFTER INSERT ON public.tenant_invitations
    FOR EACH ROW EXECUTE FUNCTION public.log_invitation_event_to_outbox();

-- 6. Outbox Cleanup Helper Function (for pg_cron or periodic maintenance)
CREATE OR REPLACE FUNCTION public.cleanup_processed_outbox_events(_days_to_keep INT DEFAULT 30)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    DELETE FROM public.outbox_events
    WHERE status = 'delivered'
      AND processed_at < (timezone('utc'::text, now()) - (_days_to_keep || ' days')::INTERVAL);
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$;
