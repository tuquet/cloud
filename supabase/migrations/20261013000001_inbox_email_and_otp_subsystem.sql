-- ============================================================================
-- TUQUET-CLOUD MIGRATION: INBOX EMAIL CATCH-ALL & OTP INTERCEPTOR SUBSYSTEM
-- Version: 20261009000001
-- Target: Supabase / PostgreSQL (inbox schema)
-- Description: Establishes the Central Control Plane for Catch-All domain management,
--              high-throughput email ingestion, smart OTP/magic link extraction,
--              realtime device fanout, and multi-tenant isolation.
-- ============================================================================

-- 1. Ensure Schema and Extensions exist
CREATE SCHEMA IF NOT EXISTS inbox;
GRANT USAGE ON SCHEMA inbox TO authenticated, service_role, anon;

-- 2. Domain & Link Enums
DO $$ BEGIN
    CREATE TYPE inbox.domain_status AS ENUM ('active', 'pending_verification', 'disabled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE inbox.link_type AS ENUM ('activation', 'password_reset', 'magic_login', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Domains Table (Multi-tenant Catch-All Domains)
CREATE TABLE IF NOT EXISTS inbox.domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    domain_name VARCHAR(255) NOT NULL,
    status inbox.domain_status NOT NULL DEFAULT 'active',
    webhook_secret VARCHAR(64) NOT NULL DEFAULT encode(extensions.gen_random_bytes(24), 'hex'),
    cloudflare_zone_id VARCHAR(64),
    catch_all_enabled BOOLEAN NOT NULL DEFAULT true,
    total_emails_received BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT uq_inbox_domains_tenant_domain UNIQUE (tenant_id, domain_name)
);

COMMENT ON TABLE inbox.domains IS 'Catch-all email domains registered to tenants for synthetic account registration';

CREATE INDEX IF NOT EXISTS idx_inbox_domains_tenant_status ON inbox.domains (tenant_id, status);

-- 4. Emails Table (Raw Ingested Messages)
CREATE TABLE IF NOT EXISTS inbox.emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    domain_id UUID REFERENCES inbox.domains(id) ON DELETE SET NULL,
    recipient TEXT NOT NULL,
    sender TEXT NOT NULL,
    subject TEXT,
    body_text TEXT,
    body_html TEXT,
    has_otp BOOLEAN NOT NULL DEFAULT false,
    assigned_browser_id UUID,
    received_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE inbox.emails IS 'Central repository of incoming emails ingested via Cloudflare Email Routing or SMTP relays';

CREATE INDEX IF NOT EXISTS idx_inbox_emails_tenant_recipient ON inbox.emails (tenant_id, recipient, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_inbox_emails_received_at ON inbox.emails (received_at);
CREATE INDEX IF NOT EXISTS idx_inbox_emails_browser ON inbox.emails (assigned_browser_id);

-- 5. OTPs Table (Extracted Verification Codes with Supabase Realtime)
CREATE TABLE IF NOT EXISTS inbox.otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    email_id UUID NOT NULL REFERENCES inbox.emails(id) ON DELETE CASCADE,
    recipient TEXT NOT NULL,
    code VARCHAR(32) NOT NULL,
    sender_service VARCHAR(64),
    is_consumed BOOLEAN NOT NULL DEFAULT false,
    consumed_by_device_id UUID,
    consumed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (timezone('utc'::text, now()) + INTERVAL '15 minutes'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE inbox.otps IS 'Extracted One-Time Passwords (OTPs) pushed in real-time to CLI runners and Automa';

CREATE INDEX IF NOT EXISTS idx_inbox_otps_lookup ON inbox.otps (tenant_id, recipient, is_consumed, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inbox_otps_device ON inbox.otps (consumed_by_device_id);

-- 6. Verification Links Table (Magic Links & Confirmations)
CREATE TABLE IF NOT EXISTS inbox.links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    email_id UUID NOT NULL REFERENCES inbox.emails(id) ON DELETE CASCADE,
    recipient TEXT NOT NULL,
    url TEXT NOT NULL,
    link_type inbox.link_type NOT NULL DEFAULT 'activation',
    is_consumed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE inbox.links IS 'Extracted verification, activation, and magic login URLs';

CREATE INDEX IF NOT EXISTS idx_inbox_links_lookup ON inbox.links (tenant_id, recipient, is_consumed, created_at DESC);

-- Attach foreign keys to runners plugin tables if runners plugin is already installed
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'runners' AND table_name = 'browsers') THEN
        ALTER TABLE inbox.emails
            DROP CONSTRAINT IF EXISTS fk_inbox_emails_assigned_browser,
            ADD CONSTRAINT fk_inbox_emails_assigned_browser
            FOREIGN KEY (assigned_browser_id) REFERENCES runners.browsers(id) ON DELETE SET NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'runners' AND table_name = 'devices') THEN
        ALTER TABLE inbox.otps
            DROP CONSTRAINT IF EXISTS fk_inbox_otps_consumed_by_device,
            ADD CONSTRAINT fk_inbox_otps_consumed_by_device
            FOREIGN KEY (consumed_by_device_id) REFERENCES runners.devices(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 7. Row Level Security Policies
ALTER TABLE inbox.domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbox.emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbox.otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbox.links ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    DROP POLICY IF EXISTS "inbox_domains_select" ON inbox.domains;
    DROP POLICY IF EXISTS "inbox_domains_manage" ON inbox.domains;
    DROP POLICY IF EXISTS "inbox_emails_select" ON inbox.emails;
    DROP POLICY IF EXISTS "inbox_otps_select" ON inbox.otps;
    DROP POLICY IF EXISTS "inbox_otps_update" ON inbox.otps;
    DROP POLICY IF EXISTS "inbox_links_select" ON inbox.links;
EXCEPTION WHEN undefined_object THEN null;
END $$;

CREATE POLICY "inbox_domains_select" ON inbox.domains
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "inbox_domains_manage" ON inbox.domains
    FOR ALL TO authenticated
    USING (public.is_tenant_admin(tenant_id));

CREATE POLICY "inbox_emails_select" ON inbox.emails
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "inbox_otps_select" ON inbox.otps
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "inbox_otps_update" ON inbox.otps
    FOR UPDATE TO authenticated
    USING (public.is_tenant_member(tenant_id));

CREATE POLICY "inbox_links_select" ON inbox.links
    FOR SELECT TO authenticated
    USING (public.is_tenant_member(tenant_id));

-- Grant access to PostgREST roles
GRANT ALL ON TABLE inbox.domains TO authenticated, service_role;
GRANT ALL ON TABLE inbox.emails TO authenticated, service_role;
GRANT ALL ON TABLE inbox.otps TO authenticated, service_role;
GRANT ALL ON TABLE inbox.links TO authenticated, service_role;

-- 8. Enable Supabase Realtime Publication on OTPs and Emails
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE inbox.otps;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE inbox.emails;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- 9. Atomic RPC Functions for Webhook Ingestion & Device OTP Consumption

-- 9.1. Ingest Email & Auto-Insert Extracted OTP/Links
CREATE OR REPLACE FUNCTION inbox.ingest_email(
    p_tenant_id UUID,
    p_recipient TEXT,
    p_sender TEXT,
    p_subject TEXT,
    p_body_text TEXT,
    p_body_html TEXT DEFAULT NULL,
    p_otp_code TEXT DEFAULT NULL,
    p_sender_service TEXT DEFAULT NULL,
    p_link_url TEXT DEFAULT NULL,
    p_link_type TEXT DEFAULT 'activation',
    p_assigned_browser_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_domain_id UUID;
    v_email_id UUID;
    v_otp_id UUID;
    v_link_id UUID;
    v_domain_name TEXT;
BEGIN
    -- Extract domain from recipient
    v_domain_name := split_part(p_recipient, '@', 2);
    
    -- Try resolving domain_id
    SELECT id INTO v_domain_id 
    FROM inbox.domains 
    WHERE tenant_id = p_tenant_id AND lower(domain_name) = lower(v_domain_name)
    LIMIT 1;

    -- Update domain email counter
    IF v_domain_id IS NOT NULL THEN
        UPDATE inbox.domains 
        SET total_emails_received = total_emails_received + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_domain_id;
    END IF;

    -- Insert Email Record
    INSERT INTO inbox.emails (
        tenant_id, domain_id, recipient, sender, subject,
        body_text, body_html, has_otp, assigned_browser_id
    ) VALUES (
        p_tenant_id, v_domain_id, lower(p_recipient), p_sender, p_subject,
        p_body_text, p_body_html, (p_otp_code IS NOT NULL AND p_otp_code <> ''), p_assigned_browser_id
    ) RETURNING id INTO v_email_id;

    -- Insert OTP Record if present
    IF p_otp_code IS NOT NULL AND p_otp_code <> '' THEN
        INSERT INTO inbox.otps (
            tenant_id, email_id, recipient, code, sender_service
        ) VALUES (
            p_tenant_id, v_email_id, lower(p_recipient), p_otp_code, p_sender_service
        ) RETURNING id INTO v_otp_id;
    END IF;

    -- Insert Link Record if present
    IF p_link_url IS NOT NULL AND p_link_url <> '' THEN
        INSERT INTO inbox.links (
            tenant_id, email_id, recipient, url, link_type
        ) VALUES (
            p_tenant_id, v_email_id, lower(p_recipient), p_link_url, p_link_type::inbox.link_type
        ) RETURNING id INTO v_link_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'email_id', v_email_id,
        'otp_id', v_otp_id,
        'link_id', v_link_id
    );
END;
$$;

-- 9.2. Atomic Consume OTP Function (Supports lookup by recipient or direct otp_id)
CREATE OR REPLACE FUNCTION inbox.consume_otp(
    p_recipient TEXT DEFAULT NULL,
    p_otp_id UUID DEFAULT NULL,
    p_device_id UUID DEFAULT NULL,
    p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_found_id UUID;
    v_code VARCHAR(32);
    v_sender_service VARCHAR(64);
    v_created_at TIMESTAMPTZ;
BEGIN
    IF p_otp_id IS NOT NULL THEN
        SELECT id, code, sender_service, created_at
        INTO v_found_id, v_code, v_sender_service, v_created_at
        FROM inbox.otps
        WHERE id = p_otp_id
          AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
          AND is_consumed = false
          AND expires_at > timezone('utc'::text, now())
        FOR UPDATE SKIP LOCKED;
    ELSE
        SELECT id, code, sender_service, created_at
        INTO v_found_id, v_code, v_sender_service, v_created_at
        FROM inbox.otps
        WHERE (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
          AND lower(recipient) = lower(p_recipient)
          AND is_consumed = false
          AND expires_at > timezone('utc'::text, now())
        ORDER BY created_at DESC
        LIMIT 1
        FOR UPDATE SKIP LOCKED;
    END IF;

    IF v_found_id IS NULL THEN
        RETURN jsonb_build_object(
            'found', false,
            'code', NULL
        );
    END IF;

    -- Mark as consumed by this device
    UPDATE inbox.otps
    SET is_consumed = true,
        consumed_by_device_id = p_device_id,
        consumed_at = timezone('utc'::text, now())
    WHERE id = v_found_id;

    RETURN jsonb_build_object(
        'found', true,
        'otp_id', v_found_id,
        'code', v_code,
        'sender_service', v_sender_service,
        'created_at', v_created_at
    );
END;
$$;

GRANT EXECUTE ON FUNCTION inbox.ingest_email TO service_role;
GRANT EXECUTE ON FUNCTION inbox.consume_otp TO authenticated, service_role;

-- 10. PostgREST Public Facades & Views (Required for standard PostgREST /rest/v1/ routing)

CREATE OR REPLACE VIEW public.inbox_emails AS
    SELECT 
        e.id,
        e.tenant_id,
        e.domain_id,
        split_part(e.recipient, '@', 2) AS domain,
        e.recipient,
        e.sender,
        e.subject,
        e.body_text,
        e.body_html,
        e.has_otp,
        e.assigned_browser_id,
        e.received_at,
        e.created_at,
        e.metadata,
        e.metadata->>'message_id' AS message_id,
        e.metadata->'raw_headers' AS raw_headers
    FROM inbox.emails e;

CREATE OR REPLACE VIEW public.inbox_otps AS
    SELECT 
        o.id,
        o.tenant_id,
        o.email_id,
        o.recipient,
        o.code,
        o.code AS otp_code,
        o.sender_service,
        o.sender_service AS service_name,
        o.is_consumed,
        o.consumed_by_device_id,
        o.consumed_by_device_id::text AS consumed_by,
        o.consumed_at,
        o.expires_at,
        o.created_at,
        o.metadata
    FROM inbox.otps o;

CREATE OR REPLACE VIEW public.inbox_domains AS
    SELECT * FROM inbox.domains;

CREATE OR REPLACE VIEW public.inbox_links AS
    SELECT * FROM inbox.links;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inbox_emails TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inbox_otps TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inbox_domains TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inbox_links TO authenticated, service_role;

-- Public Facade for ingest_email
CREATE OR REPLACE FUNCTION public.ingest_email(
    p_tenant_id UUID,
    p_recipient TEXT,
    p_sender TEXT,
    p_subject TEXT,
    p_body_text TEXT,
    p_body_html TEXT DEFAULT NULL,
    p_otp_code TEXT DEFAULT NULL,
    p_sender_service TEXT DEFAULT NULL,
    p_link_url TEXT DEFAULT NULL,
    p_link_type TEXT DEFAULT 'activation',
    p_assigned_browser_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN inbox.ingest_email(
        p_tenant_id => p_tenant_id,
        p_recipient => p_recipient,
        p_sender => p_sender,
        p_subject => p_subject,
        p_body_text => p_body_text,
        p_body_html => p_body_html,
        p_otp_code => p_otp_code,
        p_sender_service => p_sender_service,
        p_link_url => p_link_url,
        p_link_type => p_link_type,
        p_assigned_browser_id => p_assigned_browser_id
    );
END;
$$;

-- Public Facade for consume_otp
CREATE OR REPLACE FUNCTION public.consume_otp(
    p_recipient TEXT DEFAULT NULL,
    p_otp_id UUID DEFAULT NULL,
    p_device_id UUID DEFAULT NULL,
    p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN inbox.consume_otp(
        p_recipient => p_recipient,
        p_otp_id => p_otp_id,
        p_device_id => p_device_id,
        p_tenant_id => p_tenant_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ingest_email TO service_role;
GRANT EXECUTE ON FUNCTION public.consume_otp TO authenticated, service_role, anon;

