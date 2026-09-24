-- ============================================================================
-- SUPABASE SEED DATA: MULTI-TENANT ECOSYSTEM & AUTOMA CLOUD BRIDGE
-- Description: Realistic initial data for testing IAM, RBAC, Subscriptions,
--              Storage, Webhooks, and Automa Distributed Engine.
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
            id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
        )
        VALUES 
            (
                v_admin_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'admin@tuquet.dev',
                crypt('tuquet123!', gen_salt('bf')),
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Nguyen Dang Tu","avatar_url":"https://avatars.githubusercontent.com/u/tuquet"}'::jsonb,
                now(),
                now()
            ),
            (
                v_member_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'member@tuquet.dev',
                crypt('tuquet123!', gen_salt('bf')),
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Collaborator Dev","avatar_url":""}'::jsonb,
                now(),
                now()
            )
        ON CONFLICT (id) DO NOTHING;
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
ON CONFLICT (tenant_id, user_id) DO NOTHING;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
VALUES (
    'e0000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001', -- owner
    'b0000000-0000-0000-0000-000000000001'
)
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Member 2: member@tuquet.dev in acme-corp (member)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'active')
ON CONFLICT (tenant_id, user_id) DO NOTHING;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
VALUES (
    'e0000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003', -- member
    'b0000000-0000-0000-0000-000000000001'
)
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Member 3: admin@tuquet.dev in personal-dev (owner)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (tenant_id, user_id) DO NOTHING;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
VALUES (
    'e0000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001', -- owner
    'b0000000-0000-0000-0000-000000000002'
)
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


-- 6. Sample Automa Plugin Data (Optional - Only runs when automa plugin tables exist)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'automa_workflows') THEN
        INSERT INTO public.automa_workflows (
    id, tenant_id, name, description, version, status, graph_data, variables, settings, created_by
)
VALUES
    (
        'c0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'Facebook Lead Scraper & Enricher',
        'Automated workflow extracting group leads, validating phone numbers, and pushing to CRM',
        '1.2.0',
        'published',
        '{
            "nodes": [
                {"id": "node_1", "type": "trigger_manual", "data": {"label": "Manual Start"}},
                {"id": "node_2", "type": "browser_open", "data": {"url": "https://facebook.com", "headless": false}},
                {"id": "node_3", "type": "scrape_selector", "data": {"selector": ".x1y1aw7v", "attribute": "innerText"}},
                {"id": "node_4", "type": "http_post", "data": {"endpoint": "https://api.tuquet.dev/webhook/leads"}}
            ],
            "edges": [
                {"id": "e1-2", "source": "node_1", "target": "node_2"},
                {"id": "e2-3", "source": "node_2", "target": "node_3"},
                {"id": "e3-4", "source": "node_3", "target": "node_4"}
            ]
        }'::jsonb,
        '{"max_retries": 3, "timeout_seconds": 60}'::jsonb,
        '{"concurrency": 2, "proxy_profile": "socks5_default"}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'c0000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000001',
        'E-Commerce Competitor Price Monitor',
        'Periodic bot tracking competitor product catalogs and alerting price drops',
        '1.0.0',
        'draft',
        '{"nodes": [], "edges": []}'::jsonb,
        '{}'::jsonb,
        '{}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

-- 7. Sample Automa Runners (Prefix: automa_*)
INSERT INTO public.automa_runners (
    id, tenant_id, name, machine_fingerprint, status, version, os_info, ip_address, max_concurrency, active_tasks, capabilities, last_heartbeat_at
)
VALUES
    (
        'd0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'Worker-Desktop-Node-01',
        'HWID-WIN-8942-X86',
        'idle',
        '1.0.0',
        'Windows 11 Pro 64-bit',
        '192.168.1.100'::inet,
        4,
        0,
        '["browser", "http", "gui", "cdp"]'::jsonb,
        now()
    ),
    (
        'd0000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000001',
        'Cloud-VPS-Worker-SG',
        'HWID-LNX-2201-SG',
        'running',
        '1.0.0',
        'Ubuntu 22.04 LTS x86_64',
        '103.21.144.52'::inet,
        8,
        2,
        '["browser", "http", "proxy_mesh"]'::jsonb,
        now()
    )
ON CONFLICT (tenant_id, machine_fingerprint) DO UPDATE SET
    status = EXCLUDED.status,
    last_heartbeat_at = EXCLUDED.last_heartbeat_at;

-- 8. Sample Automa Campaign Runs (Prefix: automa_*)
INSERT INTO public.automa_campaign_runs (
    id, tenant_id, workflow_id, runner_id, name, status, trigger_type, total_tasks, completed_tasks, failed_tasks, progress_percent, started_at, finished_at, created_by
)
VALUES
    (
        '10000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'Daily Morning Lead Run #101',
        'completed',
        'schedule',
        50,
        50,
        0,
        100.00,
        now() - INTERVAL '2 hours',
        now() - INTERVAL '1 hour 45 minutes',
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        '10000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000002',
        'Real-time Group Extraction Batch #102',
        'running',
        'manual',
        100,
        45,
        1,
        45.00,
        now() - INTERVAL '15 minutes',
        NULL,
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

-- 9. Sample Automa Execution Logs (Prefix: automa_*)
INSERT INTO public.automa_execution_logs (
    tenant_id, campaign_run_id, runner_id, step_name, level, message, details
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'browser_open',
        'info',
        'Chromium process spawned with anti-detect flags and SOCKS5 proxy',
        '{"pid": 14208, "port": 9222}'::jsonb
    ),
    (
        'b0000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'scrape_selector',
        'info',
        'Extracted 50 candidate DOM profiles successfully',
        '{"matched_elements": 50}'::jsonb
    ),
    (
        'b0000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000002',
        'scrape_selector',
        'warn',
        'Element selector timeout on profile #44, continuing with fallback',
        '{"selector": ".x1y1aw7v", "retry_attempt": 1}'::jsonb
    );

-- 10. Sample Automa Schedules (Prefix: automa_*)
INSERT INTO public.automa_schedules (
    tenant_id, workflow_id, name, cron_expression, timezone, is_active, created_by
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001',
        'Morning Group Lead Harvesting',
        '0 8 * * *',
        'Asia/Ho_Chi_Minh',
        TRUE,
        'a0000000-0000-0000-0000-000000000001'
    )
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;
