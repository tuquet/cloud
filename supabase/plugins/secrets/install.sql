-- ============================================================================
-- Plugin: secrets — Encrypted Tenant Secret Store (device-portable)
-- ============================================================================
-- Envelope encryption:
--   KEK  (Supabase Vault secret `tq_secrets_kek`)  -> wraps
--   DEK  (one per tenant, stored wrapped in secrets.tenant_keys) -> encrypts
--   value (secrets.credentials.value_enc)
--
-- Enrolled devices authenticate with their device_token (workers.devices) and
-- fetch their tenant's secrets via SECURITY DEFINER RPCs. A brand-new device can
-- therefore obtain credentials without a human re-typing them.
--
-- Requires: pgcrypto (extensions), supabase_vault, plugins `workers` + `core-iam`.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS secrets;

COMMENT ON SCHEMA secrets IS '[Plugin: secrets] Encrypted tenant secret store (envelope: Vault KEK -> per-tenant DEK -> values)';

-- ---------------------------------------------------------------------------
-- 1. KEK accessor — reads the key-encryption key from Supabase Vault.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secrets._kek()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = vault, pg_temp
AS $$
DECLARE
    v_kek text;
BEGIN
    SELECT decrypted_secret INTO v_kek
    FROM vault.decrypted_secrets
    WHERE name = 'tq_secrets_kek'
    LIMIT 1;

    IF v_kek IS NULL THEN
        RAISE EXCEPTION 'Secret Store KEK not provisioned (vault secret "tq_secrets_kek")';
    END IF;
    RETURN v_kek;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS secrets.tenant_keys (
    tenant_id   UUID PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
    dek_enc     BYTEA NOT NULL,
    key_version INT NOT NULL DEFAULT 1,
    rotated_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
COMMENT ON TABLE secrets.tenant_keys IS '[Plugin: secrets] Per-tenant data-encryption key (DEK), wrapped with the Vault KEK';

CREATE TABLE IF NOT EXISTS secrets.credentials (
    id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    value_enc   BYTEA NOT NULL,
    key_version INT NOT NULL DEFAULT 1,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_secrets_credentials_tenant_name UNIQUE (tenant_id, name)
);
COMMENT ON TABLE secrets.credentials IS '[Plugin: secrets] Tenant-scoped encrypted credential values (referenced in workflows as {{secrets.<name>}})';

CREATE INDEX IF NOT EXISTS idx_secrets_credentials_tenant ON secrets.credentials (tenant_id, name);

-- ---------------------------------------------------------------------------
-- 3. Row Level Security — deny by default; access only through SECURITY DEFINER RPCs.
-- ---------------------------------------------------------------------------
ALTER TABLE secrets.credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE secrets.tenant_keys ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON secrets.credentials FROM anon, authenticated;
REVOKE ALL ON secrets.tenant_keys FROM anon, authenticated;

DROP POLICY IF EXISTS "secrets_credentials_service" ON secrets.credentials;
CREATE POLICY "secrets_credentials_service" ON secrets.credentials
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- 4. Internal helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secrets._get_dek(p_tenant_id UUID)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = secrets, public, extensions, pg_temp
AS $$
DECLARE
    v_dek text;
    v_enc bytea;
BEGIN
    SELECT dek_enc INTO v_enc FROM secrets.tenant_keys WHERE tenant_id = p_tenant_id;

    IF v_enc IS NULL THEN
        v_dek := encode(extensions.gen_random_bytes(32), 'hex');
        INSERT INTO secrets.tenant_keys (tenant_id, dek_enc)
        VALUES (p_tenant_id, extensions.pgp_sym_encrypt(v_dek, secrets._kek()))
        ON CONFLICT (tenant_id) DO NOTHING;
        SELECT dek_enc INTO v_enc FROM secrets.tenant_keys WHERE tenant_id = p_tenant_id;
    END IF;

    RETURN extensions.pgp_sym_decrypt(v_enc, secrets._kek());
END;
$$;

-- Verifies an enrolled device by device_id + device_token (SHA-256 hash match).
CREATE OR REPLACE FUNCTION secrets._verify_device(p_device_id UUID, p_device_token TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = workers, public, extensions, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_hash   TEXT;
BEGIN
    IF p_device_id IS NULL OR p_device_token IS NULL OR p_device_token = '' THEN
        RAISE EXCEPTION 'Device credentials required';
    END IF;

    v_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');

    SELECT tenant_id INTO v_tenant
    FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_hash;

    IF v_tenant IS NULL THEN
        RAISE EXCEPTION 'Invalid or unknown device credentials';
    END IF;
    RETURN v_tenant;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Device-authenticated RPCs (schema-local)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secrets.device_set_secret(
    p_device_id UUID, p_device_token TEXT, p_name TEXT, p_value TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = secrets, public, extensions, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_dek    TEXT;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'Secret name must not be empty';
    END IF;
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    v_dek    := secrets._get_dek(v_tenant);

    INSERT INTO secrets.credentials (tenant_id, name, value_enc)
    VALUES (v_tenant, btrim(p_name), extensions.pgp_sym_encrypt(p_value, v_dek))
    ON CONFLICT (tenant_id, name)
    DO UPDATE SET value_enc = EXCLUDED.value_enc, updated_at = timezone('utc', now());
END;
$$;

CREATE OR REPLACE FUNCTION secrets.device_list_secrets(
    p_device_id UUID, p_device_token TEXT
) RETURNS TABLE(name TEXT, updated_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = secrets, public, pg_temp
AS $$
DECLARE
    v_tenant UUID;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    RETURN QUERY
        SELECT c.name, c.updated_at
        FROM secrets.credentials c
        WHERE c.tenant_id = v_tenant
        ORDER BY c.name;
END;
$$;

-- Returns DECRYPTED secrets for an enrolled device (Device-Portable provisioning).
CREATE OR REPLACE FUNCTION secrets.device_fetch_secrets(
    p_device_id UUID, p_device_token TEXT
) RETURNS TABLE(name TEXT, value TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = secrets, public, extensions, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_dek    TEXT;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    v_dek    := secrets._get_dek(v_tenant);
    RETURN QUERY
        SELECT c.name, extensions.pgp_sym_decrypt(c.value_enc, v_dek)
        FROM secrets.credentials c
        WHERE c.tenant_id = v_tenant
        ORDER BY c.name;
END;
$$;

-- Rotates a tenant DEK: re-encrypts every credential under a fresh DEK.
CREATE OR REPLACE FUNCTION secrets.rotate_tenant_dek(
    p_device_id UUID, p_device_token TEXT
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = secrets, public, extensions, pg_temp
AS $$
DECLARE
    v_tenant UUID;
    v_old    TEXT;
    v_new    TEXT;
    v_count  INT := 0;
    r        RECORD;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    v_old := secrets._get_dek(v_tenant);

    v_new := encode(extensions.gen_random_bytes(32), 'hex');

    FOR r IN SELECT id, value_enc FROM secrets.credentials WHERE tenant_id = v_tenant LOOP
        UPDATE secrets.credentials
        SET value_enc = extensions.pgp_sym_encrypt(extensions.pgp_sym_decrypt(r.value_enc, v_old), v_new),
            key_version = key_version + 1,
            updated_at = timezone('utc', now())
        WHERE id = r.id;
        v_count := v_count + 1;
    END LOOP;

    UPDATE secrets.tenant_keys
    SET dek_enc = extensions.pgp_sym_encrypt(v_new, secrets._kek()),
        key_version = key_version + 1,
        rotated_at = timezone('utc', now())
    WHERE tenant_id = v_tenant;

    RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Public wrappers (PostgREST exposes `public` only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_secret(
    p_device_id UUID, p_device_token TEXT, p_name TEXT, p_value TEXT
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    PERFORM secrets.device_set_secret(p_device_id, p_device_token, p_name, p_value);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_secrets(
    p_device_id UUID, p_device_token TEXT
) RETURNS TABLE(name TEXT, updated_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN QUERY SELECT * FROM secrets.device_list_secrets(p_device_id, p_device_token);
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_secrets(
    p_device_id UUID, p_device_token TEXT
) RETURNS TABLE(name TEXT, value TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN QUERY SELECT * FROM secrets.device_fetch_secrets(p_device_id, p_device_token);
END;
$$;

CREATE OR REPLACE FUNCTION public.rotate_secret_dek(
    p_device_id UUID, p_device_token TEXT
) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN secrets.rotate_tenant_dek(p_device_id, p_device_token);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA secrets TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.set_secret(UUID, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_secrets(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fetch_secrets(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rotate_secret_dek(UUID, TEXT) TO anon, authenticated, service_role;

-- Register the plugin in the system catalog (best-effort, mirrors other plugins).
INSERT INTO public.system_plugins (id, name, version, schema_name, is_system, dependencies, description)
VALUES ('secrets', 'Encrypted Tenant Secret Store', '1.0.0', 'secrets', false,
        ARRAY['workers', 'core-iam'],
        'Tenant-scoped envelope-encrypted secret store (Vault KEK -> per-tenant DEK)')
ON CONFLICT (id) DO UPDATE SET version = EXCLUDED.version, description = EXCLUDED.description;
