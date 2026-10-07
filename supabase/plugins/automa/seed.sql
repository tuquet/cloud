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
