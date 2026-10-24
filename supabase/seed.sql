-- ============================================================================
-- SUPABASE SEED DATA: TUQUET ECOSYSTEM (DEVELOPMENT & QA ENVIRONMENT)
-- Description: Foundation data for Testing Admin Console & Multi-Tenancy
-- Universal Password for ALL accounts: Tuquet1102@
-- NOTE: workers.devices is NOT seeded here (dynamically enrolled via Tauri Desk)
--       automation.jobs is NOT seeded here (dynamically created on Run)
-- ============================================================================

SET search_path = public, extensions, auth;

-- 1. Create Auth Users (Supabase Auth / Local Test)
DO $$
DECLARE
    v_admin_id  UUID := 'a0000000-0000-0000-0000-000000000001'; -- Platform Superadmin
    v_owner_id  UUID := 'a0000000-0000-0000-0000-000000000002'; -- Enterprise Tenant Owner
    v_dev_id    UUID := 'a0000000-0000-0000-0000-000000000003'; -- Automation Engineer
    v_guest_id  UUID := 'a0000000-0000-0000-0000-000000000004'; -- Guest / Free User
    v_pwd_hash  TEXT := extensions.crypt('Tuquet1102@', extensions.gen_salt('bf', 10));
BEGIN
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
                'admin@tuquet.com',
                v_pwd_hash,
                now(),
                '{"provider":"email","providers":["email"],"platform_role":"superadmin"}'::jsonb,
                '{"full_name":"Nguyen Dinh Tu (Superadmin)","avatar_url":"https://avatars.githubusercontent.com/u/tuquet"}'::jsonb,
                now(), now(), '', '', '', ''
            ),
            (
                v_owner_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'owner@tuquet.dev',
                v_pwd_hash,
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Enterprise Owner","avatar_url":""}'::jsonb,
                now(), now(), '', '', '', ''
            ),
            (
                v_dev_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'dev@tuquet.dev',
                v_pwd_hash,
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Automation Engineer","avatar_url":""}'::jsonb,
                now(), now(), '', '', '', ''
            ),
            (
                v_guest_id,
                '00000000-0000-0000-0000-000000000000',
                'authenticated',
                'authenticated',
                'guest@tuquet.dev',
                v_pwd_hash,
                now(),
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"full_name":"Sandbox Guest","avatar_url":""}'::jsonb,
                now(), now(), '', '', '', ''
            )
        ON CONFLICT (id) DO UPDATE SET
            encrypted_password = EXCLUDED.encrypted_password,
            email_confirmed_at = COALESCE(auth.users.email_confirmed_at, EXCLUDED.email_confirmed_at),
            raw_app_meta_data = EXCLUDED.raw_app_meta_data,
            raw_user_meta_data = EXCLUDED.raw_user_meta_data,
            confirmation_token = '',
            recovery_token = '',
            email_change_token_new = '',
            email_change = '',
            updated_at = now();

        -- Matching auth identities for password authentication
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'identities') THEN
            INSERT INTO auth.identities (
                id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
            ) VALUES 
                (gen_random_uuid(), v_admin_id::text, v_admin_id, jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@tuquet.com'), 'email', now(), now(), now()),
                (gen_random_uuid(), v_owner_id::text, v_owner_id, jsonb_build_object('sub', v_owner_id::text, 'email', 'owner@tuquet.dev'), 'email', now(), now(), now()),
                (gen_random_uuid(), v_dev_id::text, v_dev_id, jsonb_build_object('sub', v_dev_id::text, 'email', 'dev@tuquet.dev'), 'email', now(), now(), now()),
                (gen_random_uuid(), v_guest_id::text, v_guest_id, jsonb_build_object('sub', v_guest_id::text, 'email', 'guest@tuquet.dev'), 'email', now(), now(), now())
            ON CONFLICT (provider_id, provider) DO NOTHING;
        END IF;
    END IF;

    -- Profiles in public.profiles
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES 
        (v_admin_id, 'admin@tuquet.com', 'Nguyen Dinh Tu (Superadmin)', 'https://avatars.githubusercontent.com/u/tuquet'),
        (v_owner_id, 'owner@tuquet.dev', 'Enterprise Owner', 'https://api.dicebear.com/7.x/identicon/svg?seed=owner'),
        (v_dev_id, 'dev@tuquet.dev', 'Automation Engineer', 'https://api.dicebear.com/7.x/identicon/svg?seed=dev'),
        (v_guest_id, 'guest@tuquet.dev', 'Sandbox Guest', 'https://api.dicebear.com/7.x/identicon/svg?seed=guest')
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = EXCLUDED.full_name,
        avatar_url = EXCLUDED.avatar_url;
END $$;

-- 2. Create Multi-Tenant Workspaces
INSERT INTO public.tenants (id, slug, name, avatar_url, status, metadata, created_by)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        'corp',
        'Enterprise Corp',
        'https://api.dicebear.com/7.x/identicon/svg?seed=tuquetcorp',
        'active',
        '{"plan": "enterprise", "region": "ap-southeast-1"}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        'personal-dev',
        'Personal Sandbox',
        'https://api.dicebear.com/7.x/identicon/svg?seed=personal',
        'active',
        '{"plan": "free", "region": "ap-southeast-1"}'::jsonb,
        'a0000000-0000-0000-0000-000000000004'
    )
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    metadata = EXCLUDED.metadata;

-- 3. Tenant Memberships & Role Assignments
-- 3.1. Enterprise Corp (b0...01):
-- Admin (Owner role)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.id = 'e0000000-0000-0000-0000-000000000001'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Owner (Owner role)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.id = 'e0000000-0000-0000-0000-000000000002'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- Dev (Member/Engineer role: 00000000-0000-0000-0000-000000000003)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000003', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.id = 'e0000000-0000-0000-0000-000000000003'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- 3.2. Personal Sandbox (b0...02):
-- Guest (Owner in personal sandbox)
INSERT INTO public.tenant_members (id, tenant_id, user_id, status)
VALUES ('e0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000004', 'active')
ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = EXCLUDED.status;

INSERT INTO public.member_roles (member_id, role_id, tenant_id)
SELECT tm.id, '00000000-0000-0000-0000-000000000001', tm.tenant_id
FROM public.tenant_members tm
WHERE tm.id = 'e0000000-0000-0000-0000-000000000004'
ON CONFLICT (member_id, role_id) DO NOTHING;

-- 4. Subscription Plans & Tenant Subscriptions
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'billing' AND table_name = 'plans') THEN
        INSERT INTO billing.plans (id, name, description, max_members, max_storage_mb, max_monthly_runs, price_monthly_usd, is_active)
        VALUES 
            ('free', 'Free Tier', 'Gói miễn phí trải nghiệm cơ bản', 2, 500, 100, 0.00, true),
            ('pro', 'Pro Developer', 'Dành cho cá nhân và nhóm nhỏ tự động hóa', 10, 5120, 5000, 19.00, true),
            ('enterprise', 'Enterprise Fleet', 'Dành cho doanh nghiệp quy mô lớn', 100, 51200, 100000, 99.00, true)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            price_monthly_usd = EXCLUDED.price_monthly_usd;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'billing' AND table_name = 'subscriptions') THEN
        INSERT INTO billing.subscriptions (tenant_id, plan_id, status)
        VALUES 
            ('b0000000-0000-0000-0000-000000000001', 'enterprise', 'active'),
            ('b0000000-0000-0000-0000-000000000002', 'free', 'free_tier')
        ON CONFLICT (tenant_id) DO UPDATE SET
            plan_id = EXCLUDED.plan_id,
            status = EXCLUDED.status;
    END IF;
END $$;

-- 5. Tenant Xu Wallets (Seed 10.000.000 Xu for Enterprise Corp)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'billing' AND table_name = 'wallets') THEN
        INSERT INTO billing.wallets (id, tenant_id, balance_credits, total_topped_up_credits, total_spent_credits)
        VALUES 
            ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 10000000, 10000000, 0),
            ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 0, 0, 0)
        ON CONFLICT (tenant_id) DO UPDATE SET
            balance_credits = EXCLUDED.balance_credits,
            total_topped_up_credits = EXCLUDED.total_topped_up_credits;
    END IF;
END $$;

-- 6. Central Proxy Pool (Seed 10 Proxies across VN, SG, US, JP)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workers' AND table_name = 'proxies') THEN
        INSERT INTO workers.proxies (
            id, tenant_id, host, port, protocol, country_code, city, status, latency_ms, tags, is_residential
        )
        SELECT 
            ('f0000000-0000-0000-0000-' || LPAD(i::text, 12, '0'))::uuid,
            'b0000000-0000-0000-0000-000000000001',
            '103.142.' || (100 + i) || '.45',
            8000 + i,
            'socks5',
            (ARRAY['VN', 'SG', 'US', 'JP'])[1 + (i % 4)],
            (ARRAY['Hanoi', 'Singapore', 'San Jose', 'Tokyo'])[1 + (i % 4)],
            'active',
            35 + (i * 12),
            ARRAY['Seed-Pool', (ARRAY['Residential', 'Datacenter'])[1 + (i % 2)]],
            (i % 2 = 0)
        FROM generate_series(1, 10) AS i
        ON CONFLICT (tenant_id, host, port, protocol, username) DO UPDATE SET
            status = 'active',
            latency_ms = EXCLUDED.latency_ms;
    END IF;
END $$;

-- 7. Cloud Browser Profiles (Seed 4 Idle Profiles ready for Tauri Desk execution)
-- Note: locked_by_device_id is NULL (unlocked, ready to be launched by enrolled device)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workers' AND table_name = 'browsers') THEN
        INSERT INTO workers.browsers (
            id, tenant_id, name, browser_type, engine_version,
            fingerprint_seed, os_platform, os_version, browser_brand,
            cpu_cores, ram_gb, timezone, locale, accept_languages,
            webrtc_mode, status, proxy_id, locked_by_device_id
        ) VALUES 
            (
                'c0000000-0000-0000-0000-000000000001',
                'b0000000-0000-0000-0000-000000000001',
                'FB-Lead-Harvester-01',
                'chromium', '148.0.7778.215',
                133742, 'windows', '10.0.0', 'Chrome',
                8, 16, 'Asia/Ho_Chi_Minh', 'vi-VN', 'vi-VN,vi,en-US,en',
                'proxy_shielded', 'idle',
                'f0000000-0000-0000-0000-000000000001',
                NULL
            ),
            (
                'c0000000-0000-0000-0000-000000000002',
                'b0000000-0000-0000-0000-000000000001',
                'Shopee-Price-Tracker-02',
                'chromium', '148.0.7778.215',
                998877, 'windows', '10.0.0', 'Chrome',
                8, 16, 'Asia/Ho_Chi_Minh', 'vi-VN', 'vi-VN,vi,en-US,en',
                'proxy_shielded', 'idle',
                'f0000000-0000-0000-0000-000000000002',
                NULL
            ),
            (
                'c0000000-0000-0000-0000-000000000003',
                'b0000000-0000-0000-0000-000000000001',
                'TikTok-Content-Poster-03',
                'chromium', '148.0.7778.215',
                554433, 'windows', '10.0.0', 'Chrome',
                8, 16, 'Asia/Ho_Chi_Minh', 'vi-VN', 'vi-VN,vi,en-US,en',
                'proxy_shielded', 'idle',
                'f0000000-0000-0000-0000-000000000003',
                NULL
            ),
            (
                'c0000000-0000-0000-0000-000000000004',
                'b0000000-0000-0000-0000-000000000001',
                'Global-Ad-Auditor-04',
                'chromium', '148.0.7778.215',
                776655, 'windows', '10.0.0', 'Chrome',
                8, 16, 'Asia/Ho_Chi_Minh', 'vi-VN', 'vi-VN,vi,en-US,en',
                'proxy_shielded', 'idle',
                'f0000000-0000-0000-0000-000000000004',
                NULL
            )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            status = 'idle',
            locked_by_device_id = NULL,
            proxy_id = EXCLUDED.proxy_id,
            updated_at = timezone('utc'::text, now());
    END IF;
END $$;

-- 8. Sample Workflows (Published AST graphs ready to be run)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'automation' AND table_name = 'workflows') THEN
        INSERT INTO automation.workflows (
            id, tenant_id, name, description, version, status, graph_data, settings, created_by
        ) VALUES 
            (
                'fb000000-0000-0000-0000-000000000001',
                'b0000000-0000-0000-0000-000000000001',
                'Smoke Test: Example Domain Verification',
                'Mở example.com trong Chromium headless, kiểm tra DOM và xác thực kết nối proxy',
                '1.0.0',
                'published',
                jsonb_build_object(
                    'nodes', jsonb_build_array(
                        jsonb_build_object('id', 'node-trigger', 'label', 'trigger', 'data', jsonb_build_object('type', 'manual')),
                        jsonb_build_object('id', 'node-new-tab', 'label', 'new-tab', 'data', jsonb_build_object('url', 'https://example.com', 'active', true)),
                        jsonb_build_object('id', 'node-delay', 'label', 'delay', 'data', jsonb_build_object('time', 1500))
                    ),
                    'edges', jsonb_build_array(
                        jsonb_build_object('id', 'edge-1', 'source', 'node-trigger', 'target', 'node-new-tab'),
                        jsonb_build_object('id', 'edge-2', 'source', 'node-new-tab', 'target', 'node-delay')
                    )
                ),
                '{"timeout_sec": 30}'::jsonb,
                'a0000000-0000-0000-0000-000000000001'
            ),
            (
                'fb000000-0000-0000-0000-000000000002',
                'b0000000-0000-0000-0000-000000000001',
                'E-commerce Price Monitor & Alert',
                'Quét tự động bảng giá sản phẩm, trích xuất dữ liệu và gửi thông báo khi giá biến động',
                '1.2.0',
                'published',
                jsonb_build_object(
                    'nodes', jsonb_build_array(
                        jsonb_build_object('id', 'node-trigger', 'label', 'trigger', 'data', jsonb_build_object('type', 'cron', 'cron', '0 * * * *')),
                        jsonb_build_object('id', 'node-goto', 'label', 'goto-url', 'data', jsonb_build_object('url', 'https://tuquet.com')),
                        jsonb_build_object('id', 'node-extract', 'label', 'extract-data', 'data', jsonb_build_object('selector', '.price-tag'))
                    ),
                    'edges', jsonb_build_array(
                        jsonb_build_object('id', 'edge-1', 'source', 'node-trigger', 'target', 'node-goto'),
                        jsonb_build_object('id', 'edge-2', 'source', 'node-goto', 'target', 'node-extract')
                    )
                ),
                '{"max_retries": 3}'::jsonb,
                'a0000000-0000-0000-0000-000000000001'
            )
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            graph_data = EXCLUDED.graph_data,
            updated_at = timezone('utc'::text, now());
    END IF;
END $$;

-- 9. Digital Commerce Categories, Products & Stock
DO $$
DECLARE
    v_cat_proxy UUID := 'ca000000-0000-0000-0000-000000000001';
    v_cat_soft  UUID := 'ca000000-0000-0000-0000-000000000002';
    v_cat_xu    UUID := 'ca000000-0000-0000-0000-000000000003';
    v_prod_proxy UUID := 'cb000000-0000-0000-0000-000000000001';
    v_prod_soft  UUID := 'cb000000-0000-0000-0000-000000000002';
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'commerce' AND table_name = 'categories') THEN
        INSERT INTO commerce.categories (id, slug, name, description, icon, sort_order)
        VALUES 
            (v_cat_proxy, 'proxies', 'Hạ Tầng Proxy', 'Bể proxy dân cư và datacenter tốc độ cao', 'globe', 1),
            (v_cat_soft, 'software', 'Bản Quyền Phần Mềm', 'Giấy phép kích hoạt Worker & Bot', 'cpu', 2),
            (v_cat_xu, 'xu-packages', 'Gói Nạp Xu', 'Gói tín dụng Xu nạp tiền vào ví tổ chức', 'wallet', 3)
        ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'commerce' AND table_name = 'products') THEN
        INSERT INTO commerce.products (id, category_id, slug, name, short_description, product_type, visibility)
        VALUES 
            (
                v_prod_proxy, v_cat_proxy, 'dedicated-proxy-vn-30d',
                'Gói Dedicated Proxy IPv4 VN (30 Ngày)',
                'Proxy dân cư Việt Nam tốc độ cao, băng thông không giới hạn',
                'resource', 'public'
            ),
            (
                v_prod_soft, v_cat_soft, 'worker-pro-1y',
                'Bản Quyền Worker Pro (1 Năm)',
                'Mã bản quyền kích hoạt không giới hạn worker nodes trên 1 máy trạm',
                'digital_file', 'public'
            )
        ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name;
    END IF;
END $$;

-- 10. Clean Stale Mock Devices (Ensure device list reflects ONLY real client enrollments)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workers' AND table_name = 'devices') THEN
        DELETE FROM workers.devices WHERE id IN (
            'd0000000-0000-0000-0000-000000000001',
            'd0000000-0000-0000-0000-000000000002',
            'd0000000-0000-0000-0000-000000000003'
        );
    END IF;
END $$;

-- 11. Core & Extension System Plugins Registry (SSOT)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'system_plugins') THEN
        INSERT INTO public.system_plugins (id, name, description, version, is_system, status, schema_name)
        VALUES
            ('core-iam', 'Core IAM & Workspaces', 'Nền tảng xác thực, phân quyền và quản lý tổ chức đa người dùng', '1.0.0', true, 'installed', 'public'),
            ('workers', 'Workers & Fleet Engine', 'Hạ tầng quản lý thiết bị, trình duyệt đám mây và proxy mạng', '1.0.0', true, 'installed', 'workers'),
            ('automation', 'Automation Workflow Engine', 'Bộ máy thực thi kịch bản tự động hóa đồ thị AST và chiến dịch', '1.0.0', true, 'installed', 'automation'),
            ('browsers', 'Anti-Detect Browser Profiles', 'Quản lý hạt giống vân tay trình duyệt, profile đám mây và phiên làm việc', '1.0.0', true, 'installed', 'browsers'),
            ('subscriptions', 'Billing & Subscriptions', 'Cơ chế thanh toán, gói dịch vụ định kỳ và ví điểm tín dụng', '1.0.0', true, 'installed', 'billing'),
            ('commerce', 'Digital Commerce Storefront', 'Sàn giao dịch tài nguyên số, key bản quyền và bảo hành tự động', '1.0.0', false, 'installed', 'commerce'),
            ('storage', 'Cloud Storage & Media Assets', 'Lưu trữ tài nguyên truyền thông, ảnh chụp màn hình và artifacts', '1.0.0', false, 'installed', 'media'),
            ('webhooks', 'Events & Webhooks Outbox', 'Hệ thống hàng đợi sự kiện, outbox pattern và webhook dispatch', '1.0.0', false, 'installed', 'events'),
            ('secrets', 'Encrypted Tenant Secret Store', 'Kho credential mã hoá theo tenant (Vault KEK -> DEK -> device-sealed; value mã hoá phía client)', '2.0.0', false, 'installed', 'secrets')
        ON CONFLICT (id) DO UPDATE SET 
            name = EXCLUDED.name,
            description = EXCLUDED.description,
            is_system = EXCLUDED.is_system,
            status = EXCLUDED.status,
            schema_name = EXCLUDED.schema_name,
            version = EXCLUDED.version;
    END IF;
END $$;
