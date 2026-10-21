-- ============================================================================
-- TUQUET-CLOUD PLUGIN: TRANSACTIONAL OUTBOX & WEBHOOKS (INSTALLATION SCRIPT)
-- Plugin ID: webhooks
-- Version: 1.0.0
-- Architecture: PostgreSQL Dedicated Schema Isolation (schema: events)
-- ============================================================================

-- 1. Create Dedicated Schema & Grants
CREATE SCHEMA IF NOT EXISTS events;
GRANT USAGE ON SCHEMA events TO authenticated, service_role, anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA events GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA events GRANT ALL ON FUNCTIONS TO authenticated, service_role;

-- 2. Enums & Tables in schema events
DO $$ BEGIN
    CREATE TYPE events.outbox_status AS ENUM ('pending', 'processing', 'delivered', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS events.outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status events.outbox_status NOT NULL DEFAULT 'pending',
    retry_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processed_at TIMESTAMPTZ
);

COMMENT ON TABLE events.outbox IS '[Plugin: webhooks] Transactional event queue for reliable async processing and webhook dispatching';

CREATE INDEX IF NOT EXISTS idx_events_outbox_status ON events.outbox (status, created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_events_outbox_tenant ON events.outbox (tenant_id);
CREATE INDEX IF NOT EXISTS idx_events_outbox_created_brin ON events.outbox USING brin (created_at);

CREATE TABLE IF NOT EXISTS events.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    target_url TEXT NOT NULL CHECK (target_url ~* '^https?://[^\s]+$'),
    secret TEXT NOT NULL,
    event_types TEXT[] NOT NULL DEFAULT ARRAY['*'],
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS events.deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES events.subscriptions(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES events.outbox(id) ON DELETE CASCADE,
    status_code INT,
    response_body TEXT,
    duration_ms INT,
    attempt INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_events_deliveries_created_brin ON events.deliveries USING brin (created_at);

-- 3. Event Helper, Worker Queue Claim & Automatic Core Triggers
CREATE OR REPLACE FUNCTION events.emit_event(
    _tenant_id UUID,
    _event_type TEXT,
    _payload JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_event_id UUID;
BEGIN
    -- Enforce tenant membership authorization for authenticated caller
    IF auth.uid() IS NOT NULL AND NOT public.is_tenant_member(_tenant_id) THEN
        RAISE EXCEPTION 'Access denied: Caller is not a member of tenant %', _tenant_id
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO events.outbox (tenant_id, event_type, payload, status, created_at)
    VALUES (_tenant_id, _event_type, _payload, 'pending', timezone('utc'::text, now()))
    RETURNING id INTO v_event_id;

    -- Signal background workers via zero-latency NOTIFY
    PERFORM pg_notify('events_outbox_channel', v_event_id::text);

    RETURN v_event_id;
END;
$$;

-- 3.1. High-Performance Atomic Worker Batch Claim (FOR UPDATE SKIP LOCKED)
CREATE OR REPLACE FUNCTION events.claim_outbox_batch(
    p_batch_size INT DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    tenant_id UUID,
    event_type TEXT,
    payload JSONB,
    retry_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    WITH pending_events AS (
        SELECT o.id
        FROM events.outbox o
        WHERE o.status = 'pending'
        ORDER BY o.created_at ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    )
    UPDATE events.outbox o
    SET 
        status = 'processing',
        processed_at = timezone('utc'::text, now())
    FROM pending_events pe
    WHERE o.id = pe.id
    RETURNING o.id, o.tenant_id, o.event_type, o.payload, o.retry_count;
END;
$$;

GRANT EXECUTE ON FUNCTION events.claim_outbox_batch(INT) TO service_role;

COMMENT ON FUNCTION events.emit_event IS '[Plugin: webhooks] Programmatic API to enqueue domain events into the Transactional Outbox';

CREATE OR REPLACE FUNCTION events.log_member_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM events.emit_event(
            NEW.tenant_id, 
            'member.joined', 
            jsonb_build_object('member_id', NEW.id, 'user_id', NEW.user_id, 'joined_at', NEW.joined_at)
        );
    ELSIF TG_OP = 'DELETE' THEN
        -- Only emit event if the tenant still exists (avoid FK violation on CASCADE tenant deletion)
        IF EXISTS (SELECT 1 FROM public.tenants WHERE id = OLD.tenant_id) THEN
            PERFORM events.emit_event(
                OLD.tenant_id, 
                'member.removed', 
                jsonb_build_object('member_id', OLD.id, 'user_id', OLD.user_id)
            );
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_member_outbox ON public.tenant_members;
CREATE TRIGGER trigger_log_member_outbox
    AFTER INSERT OR DELETE ON public.tenant_members
    FOR EACH ROW EXECUTE FUNCTION events.log_member_event_to_outbox();

-- 4. RLS
ALTER TABLE events.outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "outbox_select_admin" ON events.outbox;
CREATE POLICY "outbox_select_admin" ON events.outbox FOR SELECT TO authenticated
    USING (tenant_id IS NOT NULL AND public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "subscriptions_all_admin" ON events.subscriptions;
CREATE POLICY "subscriptions_all_admin" ON events.subscriptions FOR ALL TO authenticated
    USING (public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "deliveries_select_admin" ON events.deliveries;
CREATE POLICY "deliveries_select_admin" ON events.deliveries FOR SELECT TO authenticated
    USING (public.is_tenant_admin(tenant_id));

-- 5. Permissions
INSERT INTO public.permissions (id, module, description)
VALUES 
    ('webhooks:manage', 'integrations', 'Create, update, and delete outgoing webhook endpoints'),
    ('outbox:read',     'integrations', 'Inspect background outbox event stream and delivery status')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES ('webhooks:manage'), ('outbox:read')) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 6. Register Plugin in Master Registry
SELECT public.register_plugin(
    'webhooks',
    'Transactional Outbox & Webhooks',
    '1.0.0',
    'events',
    ARRAY[]::TEXT[],
    'Transactional Outbox pattern & Outbound Webhook Subscriptions',
    FALSE,
    '{"max_retries": 5}'::jsonb
);
