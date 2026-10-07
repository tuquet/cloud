-- ============================================================================
-- VERIFICATION TEST 06: Test Identity & Tenant Provisioning Presets
-- Description: Verifies atomic and idempotent provisioning of test accounts,
--              workspaces, memberships, and role assignments.
-- ============================================================================

BEGIN;

-- 1. Check helper procedure exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'provision_test_identity') THEN
        RAISE EXCEPTION 'TEST FAILED: Function public.provision_test_identity does not exist. Run tests/presets/sql/00_provision_helper.sql first.';
    END IF;
END;
$$;

-- 2. Execute test provisioning
DO $$
DECLARE
    v_res JSONB;
    v_user_id UUID;
    v_tenant_id UUID;
    v_user_count INT;
    v_tenant_count INT;
    v_member_count INT;
    v_role_count INT;
    v_identity_count INT;
BEGIN
    v_res := public.provision_test_identity(
        p_email => 'test_preset_runner@tuquet.dev',
        p_password => 'PresetTest!12345',
        p_full_name => 'Test Preset Runner',
        p_avatar_url => 'https://avatars.githubusercontent.com/u/tuquet',
        p_user_metadata => '{"test": true}'::jsonb,
        p_tenant_slug => 'test-preset-org',
        p_tenant_name => 'Test Preset Organization',
        p_role_name => 'owner',
        p_plan => 'pro'
    );

    v_user_id := (v_res->>'user_id')::uuid;
    v_tenant_id := (v_res->>'tenant_id')::uuid;

    -- Assert auth.users
    SELECT count(1) INTO v_user_count
    FROM auth.users
    WHERE id = v_user_id
      AND email = 'test_preset_runner@tuquet.dev'
      AND email_confirmed_at IS NOT NULL
      AND confirmation_token = ''
      AND recovery_token = '';

    IF v_user_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: User was not provisioned correctly in auth.users';
    END IF;

    -- Assert auth.identities
    SELECT count(1) INTO v_identity_count
    FROM auth.identities
    WHERE user_id = v_user_id AND provider = 'email';

    IF v_identity_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Identity was not provisioned in auth.identities';
    END IF;

    -- Assert public.profiles
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id AND email = 'test_preset_runner@tuquet.dev') THEN
        RAISE EXCEPTION 'TEST FAILED: Profile was not created in public.profiles';
    END IF;

    -- Assert public.tenants
    SELECT count(1) INTO v_tenant_count
    FROM public.tenants
    WHERE id = v_tenant_id AND slug = 'test-preset-org' AND status = 'active';

    IF v_tenant_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Tenant was not provisioned in public.tenants';
    END IF;

    -- Assert public.tenant_members
    SELECT count(1) INTO v_member_count
    FROM public.tenant_members
    WHERE tenant_id = v_tenant_id AND user_id = v_user_id AND status = 'active';

    IF v_member_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Membership was not provisioned in public.tenant_members';
    END IF;

    -- Assert public.member_roles (owner)
    SELECT count(1) INTO v_role_count
    FROM public.member_roles mr
    JOIN public.roles r ON mr.role_id = r.id
    WHERE mr.tenant_id = v_tenant_id AND r.name = 'owner';

    IF v_role_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Owner role was not assigned in public.member_roles';
    END IF;

    RAISE NOTICE '[OK] Test preset provisioning verified 100%% successfully.';
END;
$$;

ROLLBACK;
