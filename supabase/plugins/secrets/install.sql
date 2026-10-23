-- ============================================================================
-- Plugin: secrets — Encrypted Tenant Secret Store (v2, zero-knowledge over wire)
-- ============================================================================
-- Envelope + device key wrapping:
--   KEK   (Supabase Vault `tq_secrets_kek`) -> wraps
--   DEK   (one per tenant, `secrets.tenant_keys`) -> seals to each enrolled device
--          via pgsodium.crypto_box_seal (X25519 sealed box)
--   value (secrets.credentials.ciphertext) -> XSalsa20-Poly1305 (crypto_secretbox),
--          encrypted CLIENT-SIDE. The server NEVER receives a plaintext value.
--
-- An enrolled device:
--   1. generates an X25519 keypair locally (private key never leaves the device)
--   2. registers its public key   -> secret_register_device  -> receives the sealed DEK
--   3. pulls ciphertext + nonce   -> secret_fetch            -> decrypts locally
--
-- Requires: pgcrypto (extensions), pgsodium, supabase_vault, plugins `workers` + `core-iam`.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgsodium;

CREATE SCHEMA IF NOT EXISTS secrets;
COMMENT ON SCHEMA secrets IS '[Plugin: secrets] Tenant secret store (Vault KEK -> per-tenant DEK -> device-sealed; client-side value encryption)';

-- ---------------------------------------------------------------------------
-- 0. Migrate / drop v1 objects (idempotent re-apply)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.set_secret(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.list_secrets(uuid, text);
DROP FUNCTION IF EXISTS public.fetch_secrets(uuid, text);
DROP FUNCTION IF EXISTS public.rotate_secret_dek(uuid, text);
DROP FUNCTION IF EXISTS secrets.device_set_secret(uuid, text, text, text);
DROP FUNCTION IF EXISTS secrets.device_list_secrets(uuid, text);
DROP FUNCTION IF EXISTS secrets.device_fetch_secrets(uuid, text);
DROP FUNCTION IF EXISTS secrets.rotate_tenant_dek(uuid, text);
DROP FUNCTION IF EXISTS secrets._get_dek(uuid);
DROP FUNCTION IF EXISTS secrets._kek();
DROP TABLE IF EXISTS secrets.credentials CASCADE;

-- ---------------------------------------------------------------------------
-- 1. KEK accessor (Vault)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secrets._kek()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = vault, pg_temp AS $$
DECLARE v_kek text;
BEGIN
    SELECT decrypted_secret INTO v_kek FROM vault.decrypted_secrets WHERE name = 'tq_secrets_kek' LIMIT 1;
    IF v_kek IS NULL THEN
        RAISE EXCEPTION 'Secret Store KEK not provisioned (vault secret "tq_secrets_kek")';
    END IF;
    RETURN v_kek;
END; $$;

-- base64 helpers (Postgres `encode(...,'base64')` inserts newlines every 76 chars)
CREATE OR REPLACE FUNCTION secrets._b64(b bytea) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
    SELECT replace(encode(b, 'base64'), E'\n', '')
$$;

CREATE OR REPLACE FUNCTION secrets._unb64(t text) RETURNS bytea
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $$
    SELECT decode(replace(t, E'\n', ''), 'base64')
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
COMMENT ON TABLE secrets.tenant_keys IS '[Plugin: secrets] Per-tenant DEK (32B), wrapped with the Vault KEK';

CREATE TABLE IF NOT EXISTS secrets.credentials (
    id          UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    ciphertext  BYTEA NOT NULL,        -- XSalsa20-Poly1305 (mac||ct), encrypted client-side
    nonce       BYTEA NOT NULL,        -- 24 bytes
    key_version INT NOT NULL DEFAULT 1,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    CONSTRAINT uq_secrets_credentials_tenant_name UNIQUE (tenant_id, name)
);
COMMENT ON TABLE secrets.credentials IS '[Plugin: secrets] Tenant credentials, ciphertext only (referenced as {{secrets.<name>}})';

CREATE TABLE IF NOT EXISTS secrets.devices (
    device_id   UUID PRIMARY KEY REFERENCES workers.devices(id) ON DELETE CASCADE,
    tenant_id   UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    public_key  BYTEA NOT NULL,        -- 32B X25519
    wrapped_dek BYTEA,                 -- DEK sealed to this device (crypto_box_seal)
    key_version INT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    rotated_at  TIMESTAMPTZ
);
COMMENT ON TABLE secrets.devices IS '[Plugin: secrets] Device X25519 public key + tenant DEK sealed to it';

CREATE INDEX IF NOT EXISTS idx_secrets_credentials_tenant ON secrets.credentials (tenant_id, name);

-- ---------------------------------------------------------------------------
-- 3. RLS — deny by default; reachable only via SECURITY DEFINER RPCs
-- ---------------------------------------------------------------------------
ALTER TABLE secrets.credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE secrets.tenant_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE secrets.devices    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON secrets.credentials FROM anon, authenticated;
REVOKE ALL ON secrets.tenant_keys FROM anon, authenticated;
REVOKE ALL ON secrets.devices    FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Internal helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION secrets._get_dek(p_tenant_id UUID)
RETURNS bytea LANGUAGE plpgsql SECURITY DEFINER
SET search_path = secrets, public, extensions, pg_temp AS $$
DECLARE v_enc bytea; v_hex text;
BEGIN
    SELECT dek_enc INTO v_enc FROM secrets.tenant_keys WHERE tenant_id = p_tenant_id;
    IF v_enc IS NULL THEN
        v_hex := encode(extensions.gen_random_bytes(32), 'hex');
        INSERT INTO secrets.tenant_keys (tenant_id, dek_enc)
        VALUES (p_tenant_id, extensions.pgp_sym_encrypt(v_hex, secrets._kek()))
        ON CONFLICT (tenant_id) DO NOTHING;
        SELECT dek_enc INTO v_enc FROM secrets.tenant_keys WHERE tenant_id = p_tenant_id;
    END IF;
    RETURN decode(extensions.pgp_sym_decrypt(v_enc, secrets._kek()), 'hex');
END; $$;

CREATE OR REPLACE FUNCTION secrets._verify_device(p_device_id UUID, p_device_token TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = workers, public, extensions, pg_temp AS $$
DECLARE v_tenant UUID; v_hash TEXT;
BEGIN
    IF p_device_id IS NULL OR p_device_token IS NULL OR p_device_token = '' THEN
        RAISE EXCEPTION 'Device credentials required';
    END IF;
    v_hash := encode(extensions.digest(p_device_token, 'sha256'), 'hex');
    SELECT tenant_id INTO v_tenant FROM workers.devices
    WHERE id = p_device_id AND device_token_hash = v_hash;
    IF v_tenant IS NULL THEN
        RAISE EXCEPTION 'Invalid or unknown device credentials';
    END IF;
    RETURN v_tenant;
END; $$;

-- ---------------------------------------------------------------------------
-- 5. Device-authenticated RPCs
-- ---------------------------------------------------------------------------
-- Register the device's X25519 public key and return the DEK sealed to it.
CREATE OR REPLACE FUNCTION secrets.register_device(p_device_id UUID, p_device_token TEXT, p_public_key BYTEA)
RETURNS bytea LANGUAGE plpgsql SECURITY DEFINER
SET search_path = secrets, public, pgsodium, pg_temp AS $$
DECLARE v_tenant UUID; v_dek bytea; v_sealed bytea;
BEGIN
    IF octet_length(p_public_key) <> 32 THEN
        RAISE EXCEPTION 'X25519 public key must be 32 bytes';
    END IF;
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    v_dek    := secrets._get_dek(v_tenant);
    v_sealed := pgsodium.crypto_box_seal(v_dek, p_public_key);

    INSERT INTO secrets.devices (device_id, tenant_id, public_key, wrapped_dek, key_version, rotated_at)
    VALUES (p_device_id, v_tenant, p_public_key, v_sealed, 1, timezone('utc', now()))
    ON CONFLICT (device_id) DO UPDATE
        SET public_key = EXCLUDED.public_key, tenant_id = EXCLUDED.tenant_id,
            wrapped_dek = EXCLUDED.wrapped_dek, rotated_at = timezone('utc', now());

    RETURN v_sealed;
END; $$;

-- Re-seal and return the DEK for an already-registered device.
CREATE OR REPLACE FUNCTION secrets.deliver_dek(p_device_id UUID, p_device_token TEXT)
RETURNS bytea LANGUAGE plpgsql SECURITY DEFINER
SET search_path = secrets, public, pgsodium, pg_temp AS $$
DECLARE v_tenant UUID; v_pub bytea; v_dek bytea; v_sealed bytea;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    SELECT public_key INTO v_pub FROM secrets.devices WHERE device_id = p_device_id;
    IF v_pub IS NULL THEN
        RAISE EXCEPTION 'Device public key not registered — run secret_register_device first';
    END IF;
    v_dek    := secrets._get_dek(v_tenant);
    v_sealed := pgsodium.crypto_box_seal(v_dek, v_pub);
    UPDATE secrets.devices SET wrapped_dek = v_sealed, rotated_at = timezone('utc', now())
    WHERE device_id = p_device_id;
    RETURN v_sealed;
END; $$;

-- Store a client-encrypted value (server never sees plaintext).
CREATE OR REPLACE FUNCTION secrets.put_secret(
    p_device_id UUID, p_device_token TEXT, p_name TEXT, p_ciphertext BYTEA, p_nonce BYTEA
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = secrets, public, pg_temp AS $$
DECLARE v_tenant UUID; v_kv INT;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'Secret name must not be empty'; END IF;
    IF octet_length(p_nonce) <> 24 THEN RAISE EXCEPTION 'nonce must be 24 bytes'; END IF;
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    SELECT key_version INTO v_kv FROM secrets.tenant_keys WHERE tenant_id = v_tenant;
    INSERT INTO secrets.credentials (tenant_id, name, ciphertext, nonce, key_version)
    VALUES (v_tenant, btrim(p_name), p_ciphertext, p_nonce, COALESCE(v_kv, 1))
    ON CONFLICT (tenant_id, name) DO UPDATE
        SET ciphertext = EXCLUDED.ciphertext, nonce = EXCLUDED.nonce,
            key_version = EXCLUDED.key_version, updated_at = timezone('utc', now());
END; $$;

CREATE OR REPLACE FUNCTION secrets.list_secrets(p_device_id UUID, p_device_token TEXT)
RETURNS TABLE(name TEXT, updated_at TIMESTAMPTZ, key_version INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = secrets, public, pg_temp AS $$
DECLARE v_tenant UUID;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    RETURN QUERY SELECT c.name, c.updated_at, c.key_version FROM secrets.credentials c
        WHERE c.tenant_id = v_tenant ORDER BY c.name;
END; $$;

-- Returns ciphertext only (device decrypts locally with the sealed DEK).
CREATE OR REPLACE FUNCTION secrets.fetch_secrets(p_device_id UUID, p_device_token TEXT)
RETURNS TABLE(name TEXT, ciphertext BYTEA, nonce BYTEA, key_version INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = secrets, public, pg_temp AS $$
DECLARE v_tenant UUID;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    RETURN QUERY SELECT c.name, c.ciphertext, c.nonce, c.key_version FROM secrets.credentials c
        WHERE c.tenant_id = v_tenant ORDER BY c.name;
END; $$;

-- Rotate the tenant DEK: re-encrypt every value server-side and re-seal for all devices.
CREATE OR REPLACE FUNCTION secrets.rotate_dek(p_device_id UUID, p_device_token TEXT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = secrets, public, pgsodium, extensions, pg_temp AS $$
DECLARE
    v_tenant UUID; v_old bytea; v_new bytea; v_count INT := 0;
    v_plain bytea; v_nonce bytea; d RECORD; r RECORD;
BEGIN
    v_tenant := secrets._verify_device(p_device_id, p_device_token);
    v_old := secrets._get_dek(v_tenant);
    v_new := extensions.gen_random_bytes(32);

    FOR r IN SELECT id, ciphertext, nonce FROM secrets.credentials WHERE tenant_id = v_tenant LOOP
        v_plain := pgsodium.crypto_aead_ietf_decrypt(r.ciphertext, ''::bytea, r.nonce, v_old);
        v_nonce := extensions.gen_random_bytes(24);
        UPDATE secrets.credentials
        SET ciphertext = pgsodium.crypto_aead_ietf_encrypt(v_plain, ''::bytea, v_nonce, v_new),
            nonce = v_nonce,
            key_version = key_version + 1,
            updated_at = timezone('utc', now())
        WHERE id = r.id;
        v_count := v_count + 1;
    END LOOP;

    UPDATE secrets.tenant_keys
    SET dek_enc = extensions.pgp_sym_encrypt(encode(v_new, 'hex'), secrets._kek()),
        key_version = key_version + 1, rotated_at = timezone('utc', now())
    WHERE tenant_id = v_tenant;

    FOR d IN SELECT device_id, public_key FROM secrets.devices WHERE tenant_id = v_tenant LOOP
        UPDATE secrets.devices SET wrapped_dek = pgsodium.crypto_box_seal(v_new, d.public_key),
            rotated_at = timezone('utc', now())
        WHERE device_id = d.device_id;
    END LOOP;

    RETURN v_count;
END; $$;

-- ---------------------------------------------------------------------------
-- 6. Public wrappers (PostgREST); base64 in/out for bytea
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.secret_register_device(p_device_id UUID, p_device_token TEXT, p_public_key TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN secrets._b64(secrets.register_device(p_device_id, p_device_token, secrets._unb64(p_public_key)));
END; $$;

CREATE OR REPLACE FUNCTION public.secret_deliver_dek(p_device_id UUID, p_device_token TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN secrets._b64(secrets.deliver_dek(p_device_id, p_device_token));
END; $$;

CREATE OR REPLACE FUNCTION public.secret_put(p_device_id UUID, p_device_token TEXT, p_name TEXT, p_ciphertext TEXT, p_nonce TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    PERFORM secrets.put_secret(p_device_id, p_device_token, p_name, secrets._unb64(p_ciphertext), secrets._unb64(p_nonce));
END; $$;

CREATE OR REPLACE FUNCTION public.secret_list(p_device_id UUID, p_device_token TEXT)
RETURNS TABLE(name TEXT, updated_at TIMESTAMPTZ, key_version INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN QUERY SELECT * FROM secrets.list_secrets(p_device_id, p_device_token);
END; $$;

CREATE OR REPLACE FUNCTION public.secret_fetch(p_device_id UUID, p_device_token TEXT)
RETURNS TABLE(name TEXT, ciphertext TEXT, nonce TEXT, key_version INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN QUERY SELECT f.name, secrets._b64(f.ciphertext), secrets._b64(f.nonce), f.key_version
        FROM secrets.fetch_secrets(p_device_id, p_device_token) f;
END; $$;

CREATE OR REPLACE FUNCTION public.secret_rotate(p_device_id UUID, p_device_token TEXT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
    RETURN secrets.rotate_dek(p_device_id, p_device_token);
END; $$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA secrets TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_register_device(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_deliver_dek(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_put(UUID, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_list(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_fetch(UUID, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.secret_rotate(UUID, TEXT) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7b. Register Permissions into the Base Core Dictionary
-- ---------------------------------------------------------------------------
INSERT INTO public.permissions (id, module, description)
VALUES
    ('secrets:credentials:read',   'secrets', 'Xem danh mục credential của tenant (tên/metadata; giá trị không bao giờ được trả về)'),
    ('secrets:credentials:manage', 'secrets', 'Tạo, sửa, xoá credential và đồng bộ khoá với Cloud (push/pull)'),
    ('secrets:store:rotate',       'secrets', 'Xoay DEK của tenant và tái bọc cho mọi thiết bị đã đăng ký')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES
    ('secrets:credentials:read'), ('secrets:credentials:manage'), ('secrets:store:rotate')
) AS p(id)
WHERE r.tenant_id IS NULL AND r.name IN ('owner', 'admin')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM public.roles r
CROSS JOIN (VALUES ('secrets:credentials:read')) AS p(id)
WHERE r.tenant_id IS NULL AND r.name = 'member'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 8. Plugin catalog
-- ---------------------------------------------------------------------------
INSERT INTO public.system_plugins (id, name, version, schema_name, is_system, dependencies, description)
VALUES ('secrets', 'Encrypted Tenant Secret Store', '2.0.0', 'secrets', false,
        ARRAY['workers', 'core-iam'],
        'Tenant secret store: Vault KEK -> per-tenant DEK -> device-sealed; client-side value encryption')
ON CONFLICT (id) DO UPDATE SET version = EXCLUDED.version, description = EXCLUDED.description;
