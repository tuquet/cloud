-- ============================================================================
-- MIGRATION: 20261007000003_public_postgrest_facades.sql
-- Description: Expose public PostgREST facades for acquire_browser and release_browser,
--              and ensure default demo browser profiles exist in runners.browsers.
-- ============================================================================

-- 1. Public PostgREST Facades (Required for /rest/v1/rpc/)
CREATE OR REPLACE FUNCTION public.acquire_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.acquire_browser(p_browser_id, p_device_id, p_device_token);
END;
$$;

CREATE OR REPLACE FUNCTION public.release_browser(
    p_browser_id UUID,
    p_device_id UUID,
    p_device_token TEXT,
    p_storage_path TEXT DEFAULT NULL,
    p_storage_size_bytes BIGINT DEFAULT NULL,
    p_storage_hash TEXT DEFAULT NULL,
    p_cookies_count INT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.release_browser(
        p_browser_id, p_device_id, p_device_token,
        p_storage_path, p_storage_size_bytes, p_storage_hash,
        p_cookies_count, p_metadata
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.acquire_browser(UUID, UUID, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.release_browser(UUID, UUID, TEXT, TEXT, BIGINT, TEXT, INT, JSONB) TO authenticated, anon, service_role;

-- 2. Seed default demo browser profiles if not present in remote database
DO $$
BEGIN
    -- Ensure prerequisite default tenant exists in clean-slate test environments
    INSERT INTO public.tenants (id, slug, name, status)
    VALUES ('b0000000-0000-0000-0000-000000000001', 'acme-corp', 'Acme Corporation', 'active')
    ON CONFLICT (id) DO NOTHING;

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
END $$;
