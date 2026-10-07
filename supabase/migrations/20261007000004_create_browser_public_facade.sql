-- ============================================================================
-- MIGRATION: 20261007000004_create_browser_public_facade.sql
-- Description: Expose public PostgREST facade for runners.create_browser
--              allowing client workstations to provision new browser profiles
--              with custom PRNG seed directly via /rest/v1/rpc/create_browser.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_browser(
    p_name VARCHAR(128),
    p_fingerprint_seed BIGINT DEFAULT NULL,
    p_os_platform VARCHAR(32) DEFAULT 'windows',
    p_browser_brand VARCHAR(64) DEFAULT 'Chrome',
    p_proxy_id UUID DEFAULT NULL,
    p_custom_proxy TEXT DEFAULT NULL,
    p_timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh',
    p_locale TEXT DEFAULT 'vi-VN',
    p_cpu_cores INT DEFAULT 8,
    p_ram_gb INT DEFAULT 16,
    p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN runners.create_browser(
        p_name => p_name,
        p_fingerprint_seed => p_fingerprint_seed,
        p_os_platform => p_os_platform,
        p_browser_brand => p_browser_brand,
        p_proxy_id => p_proxy_id,
        p_custom_proxy => p_custom_proxy,
        p_timezone => p_timezone,
        p_locale => p_locale,
        p_cpu_cores => p_cpu_cores,
        p_ram_gb => p_ram_gb,
        p_tenant_id => p_tenant_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_browser(
    VARCHAR(128), BIGINT, VARCHAR(32), VARCHAR(64), UUID, TEXT, TEXT, TEXT, INT, INT, UUID
) TO authenticated, anon, service_role;
