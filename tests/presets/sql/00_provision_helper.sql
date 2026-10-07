-- ============================================================================
-- TUQUET-CLOUD TEST IDENTITY & TENANT PROVISIONING HELPER
-- Description: Stored procedure for atomic, idempotent provisioning of test
--              identities in auth.users, auth.identities, public.profiles,
--              public.tenants, public.tenant_members, and public.member_roles.
-- Architecture: Strictly compliant with CWE-426 (SET search_path = '')
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE OR REPLACE FUNCTION public.provision_test_identity(
    p_email TEXT,
    p_password TEXT,
    p_full_name TEXT DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL,
    p_user_metadata JSONB DEFAULT '{}'::jsonb,
    p_tenant_slug TEXT DEFAULT NULL,
    p_tenant_name TEXT DEFAULT NULL,
    p_tenant_avatar TEXT DEFAULT NULL,
    p_tenant_metadata JSONB DEFAULT '{}'::jsonb,
    p_role_name TEXT DEFAULT 'owner',
    p_plan TEXT DEFAULT 'pro'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_encrypted_pwd TEXT;
    v_tenant_id UUID;
    v_member_id UUID;
    v_role_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Validate mandatory inputs
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password IS NULL OR trim(p_password) = '' THEN
        RAISE EXCEPTION 'Password is required';
    END IF;

    -- Encrypt password with Blowfish bcrypt (cost 10) via extensions schema
    v_encrypted_pwd := extensions.crypt(p_password, extensions.gen_salt('bf', 10));

    -- 2. Find or Create User in auth.users
    SELECT id INTO v_user_id FROM auth.users WHERE email = lower(trim(p_email)) LIMIT 1;

    IF v_user_id IS NULL THEN
        v_user_id := extensions.gen_random_uuid();
        INSERT INTO auth.users (
            id,
            instance_id,
            aud,
            role,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            is_super_admin,
            created_at,
            updated_at,
            confirmation_token,
            recovery_token,
            email_change_token_new,
            email_change
        ) VALUES (
            v_user_id,
            '00000000-0000-0000-0000-000000000000'::uuid,
            'authenticated',
            'authenticated',
            lower(trim(p_email)),
            v_encrypted_pwd,
            now(),
            '{"provider": "email", "providers": ["email"]}'::jsonb,
            jsonb_build_object(
                'full_name', COALESCE(p_full_name, split_part(p_email, '@', 1)),
                'avatar_url', COALESCE(p_avatar_url, '')
            ) || COALESCE(p_user_metadata, '{}'::jsonb),
            false,
            now(),
            now(),
            '',
            '',
            '',
            ''
        );
    ELSE
        -- Update existing user credentials and ensure active state
        UPDATE auth.users
        SET 
            encrypted_password = v_encrypted_pwd,
            email_confirmed_at = COALESCE(email_confirmed_at, now()),
            raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
                'full_name', COALESCE(p_full_name, split_part(p_email, '@', 1)),
                'avatar_url', COALESCE(p_avatar_url, '')
            ) || COALESCE(p_user_metadata, '{}'::jsonb),
            confirmation_token = '',
            recovery_token = '',
            email_change_token_new = '',
            email_change = '',
            updated_at = now()
        WHERE id = v_user_id;
    END IF;

    -- 3. Ensure Identity in auth.identities
    INSERT INTO auth.identities (
        id,
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        extensions.gen_random_uuid(),
        v_user_id::text,
        v_user_id,
        jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(p_email))),
        'email',
        now(),
        now(),
        now()
    )
    ON CONFLICT (provider_id, provider) DO UPDATE SET
        identity_data = jsonb_build_object('sub', v_user_id::text, 'email', lower(trim(p_email))),
        updated_at = now();

    -- 4. Ensure Profile in public.profiles
    INSERT INTO public.profiles (
        id,
        email,
        full_name,
        avatar_url,
        metadata
    ) VALUES (
        v_user_id,
        lower(trim(p_email)),
        COALESCE(p_full_name, split_part(p_email, '@', 1)),
        COALESCE(p_avatar_url, ''),
        COALESCE(p_user_metadata, '{}'::jsonb)
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name,
        avatar_url = EXCLUDED.avatar_url,
        metadata = public.profiles.metadata || EXCLUDED.metadata,
        updated_at = now();

    -- 5. Tenant Provisioning (if slug provided)
    IF p_tenant_slug IS NOT NULL AND trim(p_tenant_slug) <> '' THEN
        SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = lower(trim(p_tenant_slug)) LIMIT 1;

        IF v_tenant_id IS NULL THEN
            v_tenant_id := extensions.gen_random_uuid();
            INSERT INTO public.tenants (
                id,
                slug,
                name,
                avatar_url,
                status,
                metadata,
                created_by
            ) VALUES (
                v_tenant_id,
                lower(trim(p_tenant_slug)),
                COALESCE(p_tenant_name, p_tenant_slug),
                COALESCE(p_tenant_avatar, ''),
                'active',
                COALESCE(p_tenant_metadata, '{}'::jsonb) || jsonb_build_object('plan', COALESCE(p_plan, 'free')),
                v_user_id
            );
        ELSE
            UPDATE public.tenants
            SET
                name = COALESCE(p_tenant_name, name),
                avatar_url = COALESCE(p_tenant_avatar, avatar_url),
                metadata = metadata || COALESCE(p_tenant_metadata, '{}'::jsonb) || jsonb_build_object('plan', COALESCE(p_plan, 'free')),
                updated_at = now()
            WHERE id = v_tenant_id;
        END IF;

        -- 6. Tenant Membership
        SELECT id INTO v_member_id FROM public.tenant_members
        WHERE tenant_id = v_tenant_id AND user_id = v_user_id LIMIT 1;

        IF v_member_id IS NULL THEN
            v_member_id := extensions.gen_random_uuid();
            INSERT INTO public.tenant_members (
                id,
                tenant_id,
                user_id,
                status
            ) VALUES (
                v_member_id,
                v_tenant_id,
                v_user_id,
                'active'
            );
        ELSE
            UPDATE public.tenant_members
            SET status = 'active', updated_at = now()
            WHERE id = v_member_id;
        END IF;

        -- 7. Role Assignment
        SELECT id INTO v_role_id FROM public.roles
        WHERE name = p_role_name AND (tenant_id IS NULL OR tenant_id = v_tenant_id)
        ORDER BY is_system DESC LIMIT 1;

        IF v_role_id IS NOT NULL THEN
            INSERT INTO public.member_roles (
                member_id,
                role_id,
                tenant_id
            ) VALUES (
                v_member_id,
                v_role_id,
                v_tenant_id
            )
            ON CONFLICT (member_id, role_id) DO NOTHING;

            -- If requested role is non-owner, ensure tenant retains a workspace administrator owner
            IF p_role_name <> 'owner' THEN
                DECLARE
                    v_ws_admin_id UUID;
                    v_ws_admin_mem_id UUID;
                    v_owner_rid UUID;
                BEGIN
                    SELECT id INTO v_owner_rid FROM public.roles WHERE tenant_id IS NULL AND name = 'owner' LIMIT 1;

                    -- Check if another owner exists
                    IF NOT EXISTS (
                        SELECT 1 FROM public.member_roles mr
                        JOIN public.tenant_members tm ON tm.id = mr.member_id
                        WHERE tm.tenant_id = v_tenant_id AND mr.role_id = v_owner_rid AND tm.user_id <> v_user_id
                    ) THEN
                        -- Ensure workspace administrator identity exists
                        SELECT id INTO v_ws_admin_id FROM auth.users WHERE email = 'admin@tuquet.dev' LIMIT 1;
                        IF v_ws_admin_id IS NULL THEN
                            v_ws_admin_id := extensions.gen_random_uuid();
                            INSERT INTO auth.users (
                                id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                                raw_app_meta_data, raw_user_meta_data, created_at, updated_at
                            ) VALUES (
                                v_ws_admin_id, '00000000-0000-0000-0000-000000000000'::uuid,
                                'authenticated', 'authenticated', 'admin@tuquet.dev',
                                extensions.crypt('AdminPass!12345', extensions.gen_salt('bf', 10)),
                                now(), '{"provider": "email"}'::jsonb, '{"full_name": "Workspace Administrator"}'::jsonb,
                                now(), now()
                            );
                            INSERT INTO public.profiles (id, email, full_name)
                            VALUES (v_ws_admin_id, 'admin@tuquet.dev', 'Workspace Administrator')
                            ON CONFLICT (id) DO NOTHING;
                        END IF;

                        -- Add admin as owner
                        INSERT INTO public.tenant_members (tenant_id, user_id, status)
                        VALUES (v_tenant_id, v_ws_admin_id, 'active')
                        ON CONFLICT (tenant_id, user_id) DO NOTHING
                        RETURNING id INTO v_ws_admin_mem_id;

                        IF v_ws_admin_mem_id IS NULL THEN
                            SELECT id INTO v_ws_admin_mem_id FROM public.tenant_members WHERE tenant_id = v_tenant_id AND user_id = v_ws_admin_id;
                        END IF;

                        INSERT INTO public.member_roles (member_id, role_id, tenant_id)
                        VALUES (v_ws_admin_mem_id, v_owner_rid, v_tenant_id)
                        ON CONFLICT (member_id, role_id) DO NOTHING;
                    END IF;

                    -- Now safely prune owner role from v_user_id
                    DELETE FROM public.member_roles
                    WHERE member_id = v_member_id AND role_id = v_owner_rid;
                END;
            END IF;
        END IF;

        -- 8. Optional: Setup billing subscription if billing schema is installed
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'billing' AND table_name = 'subscriptions') THEN
            INSERT INTO billing.subscriptions (
                tenant_id,
                plan_id,
                status
            ) VALUES (
                v_tenant_id,
                COALESCE(p_plan, 'free'),
                CASE WHEN COALESCE(p_plan, 'free') = 'free' THEN 'free_tier'::billing.subscription_status ELSE 'active'::billing.subscription_status END
            )
            ON CONFLICT (tenant_id) DO UPDATE SET
                plan_id = EXCLUDED.plan_id,
                status = EXCLUDED.status,
                updated_at = now();
        END IF;
    END IF;

    -- 9. Return structured payload
    v_result := jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'email', lower(trim(p_email)),
        'tenant_id', v_tenant_id,
        'tenant_slug', lower(trim(p_tenant_slug)),
        'member_id', v_member_id,
        'role_id', v_role_id,
        'role_name', p_role_name,
        'plan', COALESCE(p_plan, 'free'),
        'status', 'active'
    );

    RETURN v_result;
END;
$$;

-- Wrapper function taking a single JSONB preset definition
CREATE OR REPLACE FUNCTION public.provision_test_preset(p_preset JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN public.provision_test_identity(
        p_email => p_preset->'user'->>'email',
        p_password => p_preset->'user'->>'password',
        p_full_name => p_preset->'user'->>'full_name',
        p_avatar_url => p_preset->'user'->>'avatar_url',
        p_user_metadata => COALESCE(p_preset->'user'->'metadata', '{}'::jsonb),
        p_tenant_slug => p_preset->'tenant'->>'slug',
        p_tenant_name => p_preset->'tenant'->>'name',
        p_tenant_avatar => p_preset->'tenant'->>'avatar_url',
        p_tenant_metadata => COALESCE(p_preset->'tenant'->'metadata', '{}'::jsonb),
        p_role_name => COALESCE(p_preset->>'role', 'owner'),
        p_plan => COALESCE(p_preset->'tenant'->>'plan', 'pro')
    );
END;
$$;
