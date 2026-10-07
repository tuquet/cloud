-- ============================================================================
-- SUPABASE SEED DATA: MULTI-TENANT ECOSYSTEM
-- Description: Realistic initial data for testing Core IAM & RBAC
-- ============================================================================

-- 1. Create Auth Users (Supabase Auth Mock / Local Test)
DO $$
DECLARE
    v_admin_id UUID := 'a0000000-0000-0000-0000-000000000001';
    v_member_id UUID := 'a0000000-0000-0000-0000-000000000002';
BEGIN
    -- Check if auth.users exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (
            id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
            confirmation_token, recovery_token, email_change_token_new, email_change
        )
        VALUES 
            (
                v_admin_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'admin@tuquet.dev',
                crypt('tuquet123!', gen_salt('bf', 10)),
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Nguyen Dang Tu","avatar_url":"https://avatars.githubusercontent.com/u/tuquet"}'::jsonb,
                now(),
                now(),
                '',
                '',
                '',
                ''
            ),
            (
                v_member_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'member@tuquet.dev',
                crypt('tuquet123!', gen_salt('bf', 10)),
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Collaborator Dev","avatar_url":""}'::jsonb,
                now(),
                now(),
                '',
                '',
                '',
                ''
            )
        ON CONFLICT (id) DO UPDATE SET
            encrypted_password = EXCLUDED.encrypted_password,
            email_confirmed_at = COALESCE(auth.users.email_confirmed_at, EXCLUDED.email_confirmed_at),
            confirmation_token = '',
            recovery_token = '',
            email_change_token_new = '',
            email_change = '',
            updated_at = now();

        -- Ensure matching auth identities for password authentication
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'identities') THEN
            INSERT INTO auth.identities (
                id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
            ) VALUES 
                (
                    gen_random_uuid(),
                    v_admin_id::text,
                    v_admin_id,
                    jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@tuquet.dev'),
                    'email',
                    now(),
                    now(),
                    now()
                ),
                (
                    gen_random_uuid(),
                    v_member_id::text,
                    v_member_id,
                    jsonb_build_object('sub', v_member_id::text, 'email', 'member@tuquet.dev'),
                    'email',
                    now(),
                    now(),
                    now()
                )
            ON CONFLICT (provider_id, provider) DO NOTHING;
        END IF;
    END IF;

    -- Ensure profiles exist (in case auth trigger is bypassed in test runners)
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES 
        (v_admin_id, 'admin@tuquet.dev', 'Nguyen Dang Tu', 'https://avatars.githubusercontent.com/u/tuquet'),
        (v_member_id, 'member@tuquet.dev', 'Collaborator Dev', '')
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        avatar_url = EXCLUDED.avatar_url;
END $$;

-- 2. Create Tenants
INSERT INTO public.tenants (id, slug, name, avatar_url, status, metadata, created_by)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        'acme-corp',
        'Acme Corporation',
        'https://api.dicebear.com/7.x/identicon/svg?seed=acme',
        'active',
        '{"plan": "pro", "region": "ap-southeast-1"}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        'personal-dev',
        'Personal Workspace',
        'https://api.dicebear.com/7.x/identicon/svg?seed=personal',
        'active',
        '{"plan": "free", "region": "ap-southeast-1"}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

-- 3. Tenant Memberships & Roles
-- Member 1: admin@tuquet.dev in acme-corp (owner)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.tenant_id = 'b0000000-0000-0000-0000-000000000001' AND tm.user_id = 'a0000000-0000-0000-0000-000000000001'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Member 2: member@tuquet.dev in acme-corp (member)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000003', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.tenant_id = 'b0000000-0000-0000-0000-000000000001' AND tm.user_id = 'a0000000-0000-0000-0000-000000000002'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Member 3: admin@tuquet.dev in personal-dev (owner)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.tenant_id = 'b0000000-0000-0000-0000-000000000002' AND tm.user_id = 'a0000000-0000-0000-0000-000000000001'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- 4. Subscription Tier Seed (Optional - Only runs when subscriptions plugin is installed)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'tenant_subscriptions') THEN
        INSERT INTO public.tenant_subscriptions (tenant_id, plan_id, status)
        VALUES 
            ('b0000000-0000-0000-0000-000000000001', 'pro', 'active'),
            ('b0000000-0000-0000-0000-000000000002', 'free', 'free_tier')
        ON CONFLICT (tenant_id) DO UPDATE SET
            plan_id = EXCLUDED.plan_id,
            status = EXCLUDED.status;
    END IF;
END $$;

-- 5. Seed Pre-enrolled Runner Device & Network Proxy
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'runners' AND table_name = 'devices') THEN
        INSERT INTO runners.devices (
            id, tenant_id, name, machine_fingerprint, status, os_info,
            cpu_cores, ram_mb, capabilities, device_token_hash
        ) VALUES (
            'd0000000-0000-0000-0000-000000000003',
            'b0000000-0000-0000-0000-000000000001',
            'vps-demo-worker',
            'vps-fingerprint-demo-12345',
            'idle',
            'Linux x86_64 Ubuntu 24.04 LTS',
            8,
            16384,
            '["browser:chromium", "mv3_extension_worker", "headless", "automation:workflow_graph"]'::jsonb,
            encode(digest('tqr_demo_token_12345', 'sha256'), 'hex')
        )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            status = 'idle',
            updated_at = timezone('utc'::text, now());
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'runners' AND table_name = 'proxies') THEN
        INSERT INTO runners.proxies (
            id, tenant_id, name, protocol, host, port, status
        ) VALUES (
            'fa000000-0000-0000-0000-000000000001',
            'b0000000-0000-0000-0000-000000000001',
            'Local Bridge SOCKS5',
            'socks5',
            '127.0.0.1',
            1080,
            'active'
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- 6. Seed Cloud Browsers with C++ PRNG Fingerprints
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'runners' AND table_name = 'browsers') THEN
        INSERT INTO runners.browsers (
            id, tenant_id, name, browser_type, engine_version,
            fingerprint_seed, os_platform, os_version, browser_brand,
            cpu_cores, ram_gb, timezone, locale, accept_languages,
            webrtc_mode, status
        ) VALUES 
            (
                'c0000000-0000-0000-0000-000000000001',
                'b0000000-0000-0000-0000-000000000001',
                'FB-Ad-Spender-01',
                'chromium',
                '148.0.7778.215',
                133742,
                'windows',
                '10.0.0',
                'Chrome',
                8,
                16,
                'Asia/Ho_Chi_Minh',
                'vi-VN',
                'vi-VN,vi,en-US,en',
                'proxy_shielded',
                'idle'
            ),
            (
                'c0000000-0000-0000-0000-000000000002',
                'b0000000-0000-0000-0000-000000000001',
                'TikTok-Creator-02',
                'chromium',
                '148.0.7778.215',
                998877,
                'macos',
                '15.2.0',
                'Chrome',
                10,
                32,
                'America/New_York',
                'en-US',
                'en-US,en',
                'proxy_shielded',
                'idle'
            )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            fingerprint_seed = EXCLUDED.fingerprint_seed,
            status = 'idle',
            updated_at = timezone('utc'::text, now());
    END IF;
END $$;

-- 7. Seed Automa Workflows for E2E Automation Testing
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'automa' AND table_name = 'workflows') THEN
        INSERT INTO automa.workflows (
            id, tenant_id, local_id, name, description, version, data, is_active
        ) VALUES (
            'fb000000-0000-0000-0000-000000000001',
            'b0000000-0000-0000-0000-000000000001',
            'wf-e2e-smoke-01',
            'E2E Smoke: Check Example Domain',
            'Opens example.com in Chromium headless, delays 2 seconds, and verifies browser state',
            '1.0.0',
            jsonb_build_object(
                'nodes', jsonb_build_array(
                    jsonb_build_object('id', 'node-trigger', 'label', 'trigger', 'data', jsonb_build_object('type', 'manual')),
                    jsonb_build_object('id', 'node-new-tab', 'label', 'new-tab', 'data', jsonb_build_object('url', 'https://example.com', 'active', true)),
                    jsonb_build_object('id', 'node-delay', 'label', 'delay', 'data', jsonb_build_object('time', 2000))
                ),
                'edges', jsonb_build_array(
                    jsonb_build_object('id', 'edge-1', 'source', 'node-trigger', 'target', 'node-new-tab'),
                    jsonb_build_object('id', 'edge-2', 'source', 'node-new-tab', 'target', 'node-delay')
                )
            ),
            true
        )
        ON CONFLICT (tenant_id, local_id) DO UPDATE SET
            name = EXCLUDED.name,
            data = EXCLUDED.data,
            updated_at = timezone('utc'::text, now());
    END IF;
END $$;

