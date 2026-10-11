-- ============================================================================
-- SUPABASE MIGRATION: SEED ADMIN TUQUET ACCOUNT
-- Description: Sets up admin@tuquet.com with password Tuquet1102@
--              and primary workspace 'Nguyen Dinh Tu'
-- ============================================================================

DO $$
DECLARE
    v_admin_id UUID := 'a0000000-0000-0000-0000-000000000001';
    v_tenant_id UUID := 'b0000000-0000-0000-0000-000000000001';
BEGIN
    -- 1. Remove duplicate signup if present
    DELETE FROM auth.identities WHERE user_id <> v_admin_id AND identity_data->>'email' = 'admin@tuquet.com';
    DELETE FROM auth.users WHERE email = 'admin@tuquet.com' AND id <> v_admin_id;

    -- 2. Upsert admin user
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
    )
    VALUES (
        v_admin_id,
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        'admin@tuquet.com',
        extensions.crypt('Tuquet1102@', extensions.gen_salt('bf', 10)),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Nguyen Dinh Tu","avatar_url":"https://avatars.githubusercontent.com/u/tuquet"}'::jsonb,
        now(),
        now(),
        '', '', '', ''
    )
    ON CONFLICT (id) DO UPDATE SET
        email = 'admin@tuquet.com',
        encrypted_password = extensions.crypt('Tuquet1102@', extensions.gen_salt('bf', 10)),
        email_confirmed_at = now(),
        raw_user_meta_data = '{"full_name":"Nguyen Dinh Tu","avatar_url":"https://avatars.githubusercontent.com/u/tuquet"}'::jsonb,
        updated_at = now();

    -- 3. Upsert identity
    INSERT INTO auth.identities (
        id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(),
        v_admin_id::text,
        v_admin_id,
        jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@tuquet.com'),
        'email',
        now(),
        now(),
        now()
    )
    ON CONFLICT (provider_id, provider) DO UPDATE SET
        identity_data = jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@tuquet.com'),
        updated_at = now();

    -- 4. Upsert profile
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        v_admin_id,
        'admin@tuquet.com',
        'Nguyen Dinh Tu',
        'https://avatars.githubusercontent.com/u/tuquet'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = 'admin@tuquet.com',
        full_name = 'Nguyen Dinh Tu',
        updated_at = now();

    -- 5. Primary Workspace: Nguyen Dinh Tu
    INSERT INTO public.tenants (id, slug, name, avatar_url, status, metadata, created_by)
    VALUES (
        v_tenant_id,
        'nguyen-dinh-tu',
        'Nguyen Dinh Tu',
        'https://api.dicebear.com/7.x/identicon/svg?seed=nguyendinhtu',
        'active',
        '{"plan": "pro", "region": "ap-southeast-1"}'::jsonb,
        v_admin_id
    )
    ON CONFLICT (id) DO UPDATE SET
        name = 'Nguyen Dinh Tu',
        slug = 'nguyen-dinh-tu',
        updated_at = now();

    -- Update any personal workspace for v_admin_id
    UPDATE public.tenants
    SET name = 'Nguyen Dinh Tu'
    WHERE created_by = v_admin_id;

    -- 6. Link tenant membership
    INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
    VALUES (
        'e0000000-0000-0000-0000-000000000001',
        v_tenant_id,
        v_admin_id,
        'active'
    )
    ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = 'active';

    -- 7. Grant Owner role
    INSERT INTO public.member_roles (member_id, role_id, tenant_id)
    SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
    FROM public.tenant_members tm
    WHERE tm.tenant_id = v_tenant_id AND tm.user_id = v_admin_id
    ON CONFLICT (member_id, role_id) DO NOTHING;

END $$;
