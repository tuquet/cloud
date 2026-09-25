-- ============================================================================
-- TEST SUITE: 01_VERIFY_CORE_IAM.SQL
-- Description: Smoke and integrity verification for Tuquet Cloud Core Kernel
-- ============================================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY[
        'profiles', 'tenants', 'roles', 'permissions',
        'role_permissions', 'tenant_members', 'member_roles',
        'tenant_invitations', 'audit_logs', 'system_plugins'
    ];
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying Core Platform Tables in schema public...';
    
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing core tables in schema public: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 10 Core Tables exist in schema public.';
    END IF;

    -- Verify JWT Custom Access Token Hook
    RAISE NOTICE '>>> [TEST 2] Verifying Custom Access Token Hook...';
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'custom_access_token_hook'
    ) THEN
        RAISE EXCEPTION 'FAILED: Function public.custom_access_token_hook not found!';
    ELSE
        RAISE NOTICE ' [PASS] public.custom_access_token_hook is properly defined.';
    END IF;

    -- Verify Helper Functions
    RAISE NOTICE '>>> [TEST 3] Verifying Security Definer Authorization Helpers...';
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'public' AND p.proname = 'is_tenant_member') THEN
        RAISE EXCEPTION 'FAILED: public.is_tenant_member not found!';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'public' AND p.proname = 'has_tenant_permission') THEN
        RAISE EXCEPTION 'FAILED: public.has_tenant_permission not found!';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'public' AND p.proname = 'is_tenant_admin') THEN
        RAISE EXCEPTION 'FAILED: public.is_tenant_admin not found!';
    END IF;
    RAISE NOTICE ' [PASS] Security Definer authorization functions are verified.';
END $$;
