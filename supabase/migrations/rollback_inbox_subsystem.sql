-- ============================================================================
-- ROLLBACK MIGRATION: INBOX EMAIL CATCH-ALL & OTP SUBSYSTEM
-- Target: Supabase / PostgreSQL
-- Description: Clean teardown of inbox schema, public PostgREST facades, and views
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Initiating rollback of Inbox subsystem...';

    -- 1. Remove from Realtime Publication
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS inbox.otps;
        ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS inbox.emails;
    EXCEPTION WHEN undefined_object THEN null;
    END;

    -- 2. Drop PostgREST Public Facades
    DROP FUNCTION IF EXISTS public.ingest_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID);
    DROP FUNCTION IF EXISTS public.consume_otp(TEXT, UUID, UUID, UUID);

    -- 3. Drop PostgREST Public Views
    DROP VIEW IF EXISTS public.inbox_links;
    DROP VIEW IF EXISTS public.inbox_domains;
    DROP VIEW IF EXISTS public.inbox_otps;
    DROP VIEW IF EXISTS public.inbox_emails;

    -- 4. Drop Schema and all encapsulated tables, functions, and types
    DROP SCHEMA IF EXISTS inbox CASCADE;

    RAISE NOTICE 'Rollback complete. Inbox subsystem removed cleanly.';
END $$;
