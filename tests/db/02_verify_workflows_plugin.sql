-- ============================================================================
-- TEST SUITE: 02_VERIFY_WORKFLOWS_PLUGIN.SQL
-- Description: Verification for Workflows Cloud Bridge schema, tables, and RLS
-- ============================================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_tbl TEXT;
    v_expected_tables TEXT[] := ARRAY[
        'workflows', 'campaign_runs', 'execution_logs', 'schedules'
    ];
    v_rls_disabled TEXT[] := ARRAY[]::TEXT[];
BEGIN
    RAISE NOTICE '>>> [TEST 1] Verifying schema workflows and tables...';
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'workflows') THEN
        RAISE EXCEPTION 'FAILED: Schema workflows does not exist!';
    END IF;

    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'workflows' AND table_name = v_tbl
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: Missing tables in schema workflows: %', v_missing_tables;
    ELSE
        RAISE NOTICE ' [PASS] All 4 Workflows Tables exist in schema workflows.';
    END IF;

    -- Verify RLS is enabled on all 4 tables
    RAISE NOTICE '>>> [TEST 2] Verifying Row Level Security (RLS) enforcement...';
    FOREACH v_tbl IN ARRAY v_expected_tables LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables
            WHERE schemaname = 'workflows' AND tablename = v_tbl AND rowsecurity = true
        ) THEN
            v_rls_disabled := array_append(v_rls_disabled, v_tbl);
        END IF;
    END LOOP;

    IF array_length(v_rls_disabled, 1) > 0 THEN
        RAISE EXCEPTION 'FAILED: RLS is disabled on tables: %', v_rls_disabled;
    ELSE
        RAISE NOTICE ' [PASS] RLS is active on 100%% of schema workflows tables.';
    END IF;

    -- Verify Master Plugin Registry Entry
    RAISE NOTICE '>>> [TEST 3] Verifying Plugin Registry entry...';
    IF NOT EXISTS (
        SELECT 1 FROM public.system_plugins WHERE id = 'workflows' AND status = 'installed'
    ) THEN
        RAISE EXCEPTION 'FAILED: Plugin workflows is not registered as installed in public.system_plugins!';
    ELSE
        RAISE NOTICE ' [PASS] Plugin workflows is active in public.system_plugins.';
    END IF;

    -- Verify Atomic Permissions
    RAISE NOTICE '>>> [TEST 4] Verifying Workflows Atomic Permissions...';
    IF (SELECT count(*) FROM public.permissions WHERE module = 'workflows') < 6 THEN
        RAISE EXCEPTION 'FAILED: Fewer than 6 workflows permissions registered in public.permissions!';
    ELSE
        RAISE NOTICE ' [PASS] All 6 Workflows permissions registered successfully.';
    END IF;
END $$;
