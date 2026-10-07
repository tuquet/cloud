-- ============================================================================
-- MIGRATION: 20261007000005_list_browsers_public_facade.sql
-- Description: Expose public PostgREST facade for listing cloud browser profiles
--              with lease status, hardware fingerprint, and storage metadata.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_browsers(
    p_device_id UUID DEFAULT NULL,
    p_device_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, runners, extensions, pg_catalog
AS $$
DECLARE
    v_token_hash TEXT;
    v_tenant_id UUID;
    v_browsers JSONB;
BEGIN
    -- Authenticate Device if credentials provided
    IF p_device_id IS NOT NULL AND p_device_token IS NOT NULL THEN
        v_token_hash := encode(digest(p_device_token, 'sha256'), 'hex');
        SELECT tenant_id INTO v_tenant_id
        FROM runners.devices
        WHERE id = p_device_id AND device_token_hash = v_token_hash;
    END IF;

    -- Fallback to the first active tenant
    IF v_tenant_id IS NULL THEN
        SELECT id INTO v_tenant_id FROM public.tenants WHERE status = 'active' ORDER BY created_at ASC LIMIT 1;
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', b.id,
            'name', b.name,
            'browser_type', b.browser_type,
            'engine_version', b.engine_version,
            'status', b.status,
            'fingerprint_seed', b.fingerprint_seed,
            'os_platform', b.os_platform,
            'os_version', b.os_version,
            'browser_brand', b.browser_brand,
            'cpu_cores', b.cpu_cores,
            'ram_gb', b.ram_gb,
            'timezone', b.timezone,
            'locale', b.locale,
            'accept_languages', b.accept_languages,
            'proxy', b.custom_proxy,
            'storage_path', b.storage_path,
            'storage_size_bytes', b.storage_size_bytes,
            'storage_hash', b.storage_hash,
            'cookies_count', b.cookies_count,
            'locked_by_device_id', b.locked_by_device_id,
            'locked_at', b.locked_at,
            'last_synced_at', b.last_synced_at,
            'updated_at', b.updated_at
        ) ORDER BY b.created_at ASC
    ), '[]'::jsonb) INTO v_browsers
    FROM runners.browsers b
    WHERE b.tenant_id = v_tenant_id;

    RETURN v_browsers;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_browsers(UUID, TEXT) TO authenticated, anon, service_role;
