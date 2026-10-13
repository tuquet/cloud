-- ============================================================================
-- TEST SUITE: 07_VERIFY_INBOX_SUBSYSTEM.SQL
-- Description: Verification for Inbox Catch-All & OTP Interceptor Subsystem
-- ============================================================================

DO $$
DECLARE
    v_test_tenant_id UUID;
    v_ingest_res JSONB;
    v_consume_res JSONB;
    v_otp_code TEXT := '839201';
    v_test_recipient TEXT := 'acceptance_test@testmmo.dev';
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema inbox and tables...';
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'inbox') THEN
        RAISE EXCEPTION 'FAILED: Schema inbox does not exist!';
    END IF;

    -- Verify all 4 tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'inbox' AND table_name = 'domains') THEN
        RAISE EXCEPTION 'FAILED: Table inbox.domains does not exist!';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'inbox' AND table_name = 'emails') THEN
        RAISE EXCEPTION 'FAILED: Table inbox.emails does not exist!';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'inbox' AND table_name = 'otps') THEN
        RAISE EXCEPTION 'FAILED: Table inbox.otps does not exist!';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'inbox' AND table_name = 'links') THEN
        RAISE EXCEPTION 'FAILED: Table inbox.links does not exist!';
    END IF;

    RAISE NOTICE ' [PASS] Schema inbox and tables (domains, emails, otps, links) exist.';

    -- Verify RLS is enabled on all tables
    RAISE NOTICE '>>> [TEST 2] Verifying Row Level Security (RLS) enforcement...';
    IF EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'inbox' AND tablename IN ('domains', 'emails', 'otps', 'links') AND rowsecurity = false
    ) THEN
        RAISE EXCEPTION 'FAILED: One or more tables in schema inbox lack RLS!';
    ELSE
        RAISE NOTICE ' [PASS] RLS is active on all inbox tables.';
    END IF;

    -- Verify RPC functions exist
    RAISE NOTICE '>>> [TEST 3] Verifying RPC Functions ingest_email and consume_otp...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'inbox' AND p.proname = 'ingest_email'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC function inbox.ingest_email does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'inbox' AND p.proname = 'consume_otp'
    ) THEN
        RAISE EXCEPTION 'FAILED: RPC function inbox.consume_otp does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'ingest_email'
    ) THEN
        RAISE EXCEPTION 'FAILED: PostgREST facade public.ingest_email does not exist!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'consume_otp'
    ) THEN
        RAISE EXCEPTION 'FAILED: PostgREST facade public.consume_otp does not exist!';
    END IF;

    -- Verify PostgREST views exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'inbox_emails') OR
       NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'inbox_otps') THEN
        RAISE EXCEPTION 'FAILED: PostgREST views public.inbox_emails or public.inbox_otps do not exist!';
    ELSE
        RAISE NOTICE ' [PASS] All RPC functions and public PostgREST facades exist.';
    END IF;

    -- Verify Realtime Publication
    RAISE NOTICE '>>> [TEST 4] Verifying Supabase Realtime publication...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'inbox' AND tablename = 'otps'
    ) THEN
        RAISE EXCEPTION 'FAILED: inbox.otps is not included in supabase_realtime publication!';
    ELSE
        RAISE NOTICE ' [PASS] inbox.otps is published to Supabase Realtime.';
    END IF;

    -- Verify Functional Roundtrip (Ingest -> OTP Extraction -> Consume)
    RAISE NOTICE '>>> [TEST 5] Verifying Functional Ingestion & Consumption RPC Flow...';
    
    -- Select first existing tenant or create temp mock
    SELECT id INTO v_test_tenant_id FROM public.tenants LIMIT 1;
    IF v_test_tenant_id IS NULL THEN
        v_test_tenant_id := gen_random_uuid();
        INSERT INTO public.tenants (id, name, slug) VALUES (v_test_tenant_id, 'Test Acceptance Tenant', 'test-tenant-inbox');
    END IF;

    -- 5.1 Call ingest_email
    v_ingest_res := inbox.ingest_email(
        p_tenant_id => v_test_tenant_id,
        p_recipient => v_test_recipient,
        p_sender => 'security@facebookmail.com',
        p_subject => 'Your verification code is 839201',
        p_body_text => 'Enter code 839201 to verify your account.',
        p_body_html => '<p>Enter code <b>839201</b></p>',
        p_otp_code => v_otp_code,
        p_sender_service => 'Facebook',
        p_link_url => 'https://facebook.com/confirm?code=839201',
        p_link_type => 'activation'
    );

    IF (v_ingest_res ->> 'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'FAILED: ingest_email returned false or error: %', v_ingest_res;
    END IF;

    RAISE NOTICE ' [PASS] Ingestion successful. Email ID: %, OTP ID: %', v_ingest_res ->> 'email_id', v_ingest_res ->> 'otp_id';

    -- 5.2 Call consume_otp
    v_consume_res := inbox.consume_otp(
        p_tenant_id => v_test_tenant_id,
        p_recipient => v_test_recipient,
        p_device_id => NULL
    );

    IF (v_consume_res ->> 'found')::boolean IS NOT TRUE OR (v_consume_res ->> 'code') <> v_otp_code THEN
        RAISE EXCEPTION 'FAILED: consume_otp did not return expected code: %', v_consume_res;
    END IF;

    RAISE NOTICE ' [PASS] consume_otp successfully locked and consumed code: %', v_consume_res ->> 'code';

    -- 5.3 Verify second consume returns found = false (idempotence / anti-duplicate)
    v_consume_res := inbox.consume_otp(
        p_tenant_id => v_test_tenant_id,
        p_recipient => v_test_recipient,
        p_device_id => NULL
    );

    IF (v_consume_res ->> 'found')::boolean IS TRUE THEN
        RAISE EXCEPTION 'FAILED: Second consume_otp should return found=false for already consumed OTP!';
    END IF;

    RAISE NOTICE ' [PASS] Second consume_otp correctly returned found=false.';

    -- Clean up test records
    DELETE FROM inbox.emails WHERE recipient = lower(v_test_recipient);

    RAISE NOTICE '====================================================================';
    RAISE NOTICE ' [ALL TESTS PASSED] Inbox Subsystem Verification Complete!';
    RAISE NOTICE '====================================================================';
END $$;
