-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMA CLOUD BRIDGE (MOCK SEED DATA)
-- Plugin Name: automa
-- Description: Realistic initial data for testing Workflows, Runners, Campaigns
--              and Telemetry logs when Automa plugin is installed.
-- ============================================================================

-- 1. Sample Automa Workflows
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

-- 2. Sample Automa Runners
INSERT INTO public.automa_runners (
    id, tenant_id, name, machine_fingerprint, status, version, os_info, ip_address, max_concurrency, active_tasks, capabilities, last_heartbeat_at
)
VALUES
    (
        'd0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'Worker-Desktop-Node-01',
        'hwid-win11-a83f9e2b10c94d3',
        'idle',
        '1.0.4',
        'Windows 11 Pro 64-bit',
        '192.168.1.150',
        4,
        0,
        '["browser", "http", "gui", "anti-detect"]'::jsonb,
        now()
    ),
    (
        'd0000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000001',
        'Worker-Cloud-VPS-01',
        'hwid-ubuntu24-f720ac992e104',
        'running',
        '1.0.4',
        'Ubuntu 24.04 LTS x86_64',
        '103.152.220.45',
        8,
        2,
        '["browser", "http", "captcha-solver"]'::jsonb,
        now()
    )
ON CONFLICT (tenant_id, machine_fingerprint) DO NOTHING;

-- 3. Sample Automa Campaign Runs
INSERT INTO public.automa_campaign_runs (
    id, tenant_id, workflow_id, runner_id, name, status, total_tasks, completed_tasks, failed_tasks, parameters, result_summary, started_at, triggered_by
)
VALUES
    (
        'e0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000002',
        'Daily Morning Lead Scrape #1042',
        'running',
        50,
        28,
        1,
        '{"target_group": "growth_hackers_vn", "depth": 10}'::jsonb,
        '{"scraped_records": 28, "phone_numbers_found": 19}'::jsonb,
        now() - INTERVAL '15 minutes',
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

-- 4. Sample Automa Execution Logs
INSERT INTO public.automa_execution_logs (
    tenant_id, campaign_run_id, node_id, step_name, level, message, payload, logged_at
)
VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        'e0000000-0000-0000-0000-000000000001',
        'node_1',
        'trigger_manual',
        'info',
        'Campaign initiated by admin@tuquet.dev',
        '{"trigger_type": "manual"}'::jsonb,
        now() - INTERVAL '15 minutes'
    ),
    (
        'b0000000-0000-0000-0000-000000000001',
        'e0000000-0000-0000-0000-000000000001',
        'node_2',
        'browser_open',
        'info',
        'Chromium headless session spawned successfully with anti-detect profile',
        '{"ws_endpoint": "ws://127.0.0.1:9222/devtools/page/xyz"}'::jsonb,
        now() - INTERVAL '14 minutes'
    )
ON CONFLICT (id) DO NOTHING;

-- 5. Sample Automa Schedules
INSERT INTO public.automa_schedules (
    id, tenant_id, workflow_id, name, cron_expression, timezone, is_active, created_by
)
VALUES
    (
        'f0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001',
        'Daily 08:00 AM Lead Harvest',
        '0 8 * * *',
        'Asia/Ho_Chi_Minh',
        TRUE,
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;
