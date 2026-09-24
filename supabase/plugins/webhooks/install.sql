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

CREATE TABLE IF NOT EXISTS events.subscriptions (
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

-- 3. Automatic Outbox Trigger on Core Projects
CREATE OR REPLACE FUNCTION events.log_project_event_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO events.outbox (tenant_id, event_type, payload)
        VALUES (NEW.tenant_id, 'project.created', jsonb_build_object('id', NEW.id, 'name', NEW.name, 'created_at', NEW.created_at));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO events.outbox (tenant_id, event_type, payload)
        VALUES (OLD.tenant_id, 'project.deleted', jsonb_build_object('id', OLD.id, 'name', OLD.name));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_log_project_outbox ON public.projects;
CREATE TRIGGER trigger_log_project_outbox
    AFTER INSERT OR DELETE ON public.projects
    FOR EACH ROW EXECUTE FUNCTION events.log_project_event_to_outbox();

-- 4. RLS
ALTER TABLE events.outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "outbox_select_admin" ON events.outbox FOR SELECT TO authenticated
    USING (tenant_id IS NOT NULL AND public.is_tenant_admin(tenant_id));

CREATE POLICY "subscriptions_all_admin" ON events.subscriptions FOR ALL TO authenticated
    USING (public.is_tenant_admin(tenant_id));

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
    '{"max_retries": 5}'::jsonb
);
