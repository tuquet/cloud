-- ============================================================================
-- TUQUET-CLOUD PLUGIN: WORKERS (SEED DATA)
-- Description: Foundation proxies and cloud browser profiles
-- NOTE: WORKERS.devices is NOT seeded here.
--       Physical devices/workstations are dynamically enrolled via Tauri Desk
--       or 'tuquet worker start' using the RPC function WORKERS.enroll_device().
-- ============================================================================

-- Ensure a default local gateway proxy is available for testing
INSERT INTO workers.proxies (
    id, tenant_id, host, port, protocol, country_code, city, status, latency_ms, tags
) VALUES (
    'fa000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    '127.0.0.1',
    1080,
    'socks5',
    'VN',
    'Local Bridge',
    'active',
    5,
    ARRAY['Local Bridge SOCKS5', 'Tuquet-Bridge']
) ON CONFLICT (id) DO NOTHING;
