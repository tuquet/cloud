-- ============================================================================
-- TUQUET-CLOUD PLUGIN: AUTOMA CLOUD BRIDGE (MOCK SEED DATA)
-- Schema: automa
-- ============================================================================

INSERT INTO automa.workflows (
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
        '{"nodes": [], "edges": []}'::jsonb,
        '{"max_retries": 3}'::jsonb,
        '{"concurrency": 2}'::jsonb,
        'a0000000-0000-0000-0000-000000000001'
    )
ON CONFLICT (id) DO NOTHING;

INSERT INTO automa.runners (
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
        '["browser", "http", "gui"]'::jsonb,
        now()
    )
ON CONFLICT (tenant_id, machine_fingerprint) DO NOTHING;
