-- ============================================================================
-- SUPABASE MIGRATION: BASE PLATFORM CORE & KERNEL ENGINE
-- Version: 20260920000001
-- Target: Supabase / PostgreSQL (Base Core Infrastructure)
-- Description: Unifies foundational Multi-tenant Identity & Access Management (IAM),
--              Role-Based Access Control (RBAC), Security Definer Helpers,
--              Custom Access Token Claims Hook, and Master System Plugin Registry.
-- ============================================================================

-- Bật phần mở rộng cần thiết
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Đảm bảo các schema ứng dụng cốt lõi tồn tại cho PostgREST và Plugin Engine
CREATE SCHEMA IF NOT EXISTS automa;
CREATE SCHEMA IF NOT EXISTS media;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS events;

GRANT USAGE ON SCHEMA automa TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA media TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA billing TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA events TO anon, authenticated, service_role;

-- ============================================================================
-- 1. ENUMS & KIỂU DỮ LIỆU CỐT LÕI
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE public.tenant_status AS ENUM ('active', 'suspended', 'archived');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.membership_status AS ENUM ('active', 'suspended');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.invitation_status AS ENUM ('pending', 'accepted', 'revoked', 'expired');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.plugin_status AS ENUM ('installed', 'disabled', 'uninstalled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 2. ĐỊNH NGHĨA CÁC BẢNG NỀN TẢNG (CORE TABLE DEFINITIONS)
-- ============================================================================

-- 2.1. Hồ sơ người dùng mở rộng (1:1 với auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.2. Bảng Tổ chức / Workspace (Tenant Boundary)
CREATE TABLE IF NOT EXISTS public.tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(63) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    status public.tenant_status NOT NULL DEFAULT 'active',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.3. Bảng Vai trò (Roles) - Hỗ trợ cả System Role và Custom Tenant Role
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE, -- NULL = System Role
    name VARCHAR(64) NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Đảm bảo tên vai trò là duy nhất: System roles (tenant_id IS NULL) và Tenant roles (tenant_id IS NOT NULL)
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_system_name_unique 
    ON public.roles (name) WHERE tenant_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_tenant_name_unique 
    ON public.roles (tenant_id, name) WHERE tenant_id IS NOT NULL;

-- 2.4. Bảng Quyền hạn nguyên tử (Permissions Dictionary)
CREATE TABLE IF NOT EXISTS public.permissions (
    id VARCHAR(64) PRIMARY KEY, -- Format: 'module:action' (vd: 'tenants:update')
    module VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.5. Bảng Phân quyền cho Vai trò (Role <-> Permissions)
CREATE TABLE IF NOT EXISTS public.role_permissions (
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id VARCHAR(64) NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (role_id, permission_id)
);

-- 2.6. Bảng Thành viên Tổ chức (Tenant Members)
CREATE TABLE IF NOT EXISTS public.tenant_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status public.membership_status NOT NULL DEFAULT 'active',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_tenant_user UNIQUE (tenant_id, user_id)
);

-- 2.7. Bảng Gán Vai trò cho Thành viên (Member <-> Roles)
CREATE TABLE IF NOT EXISTS public.member_roles (
    member_id UUID NOT NULL REFERENCES public.tenant_members(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (member_id, role_id)
);

-- 2.8. Bảng Lời mời gia nhập Tổ chức (Tenant Invitations)
CREATE TABLE IF NOT EXISTS public.tenant_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    invited_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status public.invitation_status NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.9. Bảng Nhật ký kiểm toán an ninh (Audit Logs - Sequential Identity Clustered)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.10. Bảng Đăng ký Plugin Hệ thống (Master System Plugin Registry)
CREATE TABLE IF NOT EXISTS public.system_plugins (
    id VARCHAR(64) PRIMARY KEY,                  -- vd: 'core-iam', 'automa', 'storage', 'subscriptions', 'webhooks'
    name VARCHAR(128) NOT NULL,
    version VARCHAR(32) NOT NULL DEFAULT '1.0.0',
    schema_name VARCHAR(64) NOT NULL UNIQUE,     -- vd: 'public', 'automa', 'media', 'billing', 'events'
    status public.plugin_status NOT NULL DEFAULT 'installed',
    is_system BOOLEAN NOT NULL DEFAULT false,    -- TRUE = Bất biến (Core Kernel), FALSE = On-demand plugin
    dependencies TEXT[] NOT NULL DEFAULT '{}',   -- vd: ARRAY['storage']
    description TEXT,
    installed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    installed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.system_plugins IS 'Master registry tracking all core and dynamically installed plugins/schemas in the BaaS instance';

-- ============================================================================
-- 3. CHỈ MỤC HIỆU NĂNG CAO (SCALABLE COMPOSITE INDEXES)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_tenants_status ON public.tenants(status);
CREATE INDEX IF NOT EXISTS idx_tenants_created_by ON public.tenants(created_by);
CREATE INDEX IF NOT EXISTS idx_roles_tenant_id ON public.roles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_members_user_status ON public.tenant_members(user_id, status);
CREATE INDEX IF NOT EXISTS idx_tenant_members_tenant_user ON public.tenant_members(tenant_id, user_id);
CREATE INDEX IF NOT EXISTS idx_member_roles_role_id ON public.member_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_member_roles_tenant_id ON public.member_roles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_invitations_tenant_status ON public.tenant_invitations(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_invitations_email ON public.tenant_invitations(email);
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_time ON public.audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(tenant_id, actor_id);
CREATE INDEX IF NOT EXISTS idx_system_plugins_status ON public.system_plugins(status);
CREATE INDEX IF NOT EXISTS idx_system_plugins_schema ON public.system_plugins(schema_name);
CREATE INDEX IF NOT EXISTS idx_system_plugins_is_system ON public.system_plugins(is_system);

-- ============================================================================
-- 4.0. Safe UUID Type Cast Helper (Prevents unhandled runtime syntax errors on malformed input)
CREATE OR REPLACE FUNCTION public.safe_cast_uuid(val text)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
    RETURN val::uuid;
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_tenant_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT tm.tenant_id
    FROM public.tenant_members tm
    WHERE tm.user_id = (SELECT auth.uid())
      AND tm.status = 'active';
$$;

CREATE OR REPLACE FUNCTION public.is_tenant_member(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tenant_members tm
        WHERE tm.tenant_id = _tenant_id
          AND tm.user_id = (SELECT auth.uid())
          AND tm.status = 'active'
    );
$$;

CREATE OR REPLACE FUNCTION public.has_tenant_permission(
    _tenant_id UUID,
    _permission_id VARCHAR(64)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.tenant_members tm
        JOIN public.member_roles mr ON mr.member_id = tm.id
        JOIN public.role_permissions rp ON rp.role_id = mr.role_id
        WHERE tm.tenant_id = _tenant_id
          AND tm.user_id = (SELECT auth.uid())
          AND tm.status = 'active'
          AND rp.permission_id = _permission_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_tenant_admin(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.tenant_members tm
        JOIN public.member_roles mr ON mr.member_id = tm.id
        JOIN public.roles r ON r.id = mr.role_id
        WHERE tm.tenant_id = _tenant_id
          AND tm.user_id = (SELECT auth.uid())
          AND tm.status = 'active'
          AND r.name IN ('owner', 'admin')
    );
END;
$$;

-- 4.5. Custom Access Token Hook với giới hạn an toàn 25 Tenants (<8KB Header)
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    claims JSONB;
    user_tenants JSONB;
BEGIN
    -- Null safety: If not an authenticated user event, return untouched
    IF event->>'user_id' IS NULL OR event->'claims' IS NULL THEN
        RETURN event;
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'tenant_id', tm.tenant_id,
                'roles', (
                    SELECT jsonb_agg(r.name)
                    FROM public.member_roles mr
                    JOIN public.roles r ON r.id = mr.role_id
                    WHERE mr.member_id = tm.id
                )
            )
        ),
        '[]'::jsonb
    )
    INTO user_tenants
    FROM (
        SELECT tm.id, tm.tenant_id
        FROM public.tenant_members tm
        WHERE tm.user_id = (event->>'user_id')::uuid
          AND tm.status = 'active'
        ORDER BY tm.joined_at ASC
        LIMIT 25 -- Bảo vệ kích thước JWT header < 8KB khi user tham gia nhiều tenant
    ) tm;

    claims := event->'claims';
    claims := jsonb_set(claims, '{app_metadata,tenants}', user_tenants);
    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

-- Cấp quyền thực thi an toàn cho GoTrue Auth Daemon
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM authenticated, anon, public;

-- ============================================================================
-- 5. PLUGIN LIFECYCLE RPCs (ĐỘNG CƠ QUẢN LÝ VÒNG ĐỜI PLUGIN)
-- ============================================================================

-- 5.1. Register Plugin Function
CREATE OR REPLACE FUNCTION public.register_plugin(
    p_id VARCHAR(64),
    p_name VARCHAR(128),
    p_version VARCHAR(32),
    p_schema_name VARCHAR(64),
    p_dependencies TEXT[] DEFAULT '{}',
    p_description TEXT DEFAULT NULL,
    p_is_system BOOLEAN DEFAULT false,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.system_plugins (
        id, name, version, schema_name, status, is_system, dependencies, description, installed_by, metadata, installed_at
    )
    VALUES (
        p_id, p_name, p_version, p_schema_name, 'installed', p_is_system, p_dependencies, p_description, auth.uid(), p_metadata, timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        version = EXCLUDED.version,
        schema_name = EXCLUDED.schema_name,
        status = 'installed',
        is_system = EXCLUDED.is_system,
        dependencies = EXCLUDED.dependencies,
        description = EXCLUDED.description,
        metadata = EXCLUDED.metadata,
        installed_at = timezone('utc'::text, now());
END;
$$;

-- 5.2. Unregister Plugin Function (Bảo vệ Core Kernel & Kiểm tra phụ thuộc đảo)
CREATE OR REPLACE FUNCTION public.unregister_plugin(
    p_id VARCHAR(64)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_is_system BOOLEAN;
    v_dependent_plugin TEXT;
BEGIN
    -- 1. Kiểm tra nếu là Core System Plugin (Bất biến, không thể gỡ bỏ)
    SELECT is_system INTO v_is_system
    FROM public.system_plugins
    WHERE id = p_id;

    IF v_is_system IS TRUE THEN
        RAISE EXCEPTION 'Cannot unregister core system plugin "%": Foundation components are immutable.', p_id
            USING ERRCODE = '55000';
    END IF;

    -- 2. Kiểm tra phụ thuộc đảo (Reverse Dependency Check)
    SELECT id INTO v_dependent_plugin
    FROM public.system_plugins
    WHERE status = 'installed' AND p_id = ANY(dependencies)
    LIMIT 1;

    IF v_dependent_plugin IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot unregister plugin "%": Plugin "%" depends on it.', p_id, v_dependent_plugin
            USING ERRCODE = '23503';
    END IF;

    DELETE FROM public.system_plugins WHERE id = p_id;
END;
$$;

-- 5.3. Get Installed Plugins Function
CREATE OR REPLACE FUNCTION public.get_installed_plugins()
RETURNS TABLE (
    id VARCHAR(64),
    name VARCHAR(128),
    version VARCHAR(32),
    schema_name VARCHAR(64),
    status public.plugin_status,
    is_system BOOLEAN,
    dependencies TEXT[],
    description TEXT,
    installed_at TIMESTAMPTZ,
    metadata JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sp.id, sp.name, sp.version, sp.schema_name, sp.status, sp.is_system, sp.dependencies, sp.description, sp.installed_at, sp.metadata
    FROM public.system_plugins sp
    WHERE sp.status = 'installed'
    ORDER BY sp.is_system DESC, sp.installed_at ASC;
END;
$$;

-- ============================================================================
-- 6. DATABASE TRIGGERS TỰ ĐỘNG HÓA
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_tenants_updated_at ON public.tenants;
CREATE TRIGGER set_tenants_updated_at BEFORE UPDATE ON public.tenants FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_roles_updated_at ON public.roles;
CREATE TRIGGER set_roles_updated_at BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_tenant_members_updated_at ON public.tenant_members;
CREATE TRIGGER set_tenant_members_updated_at BEFORE UPDATE ON public.tenant_members FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', '')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_tenant_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    owner_role_id UUID;
    new_member_id UUID;
BEGIN
    IF NEW.created_by IS NOT NULL THEN
        SELECT id INTO owner_role_id
        FROM public.roles
        WHERE tenant_id IS NULL AND name = 'owner'
        LIMIT 1;

        INSERT INTO public.tenant_members (tenant_id, user_id, status)
        VALUES (NEW.id, NEW.created_by, 'active')
        RETURNING id INTO new_member_id;

        IF owner_role_id IS NOT NULL AND new_member_id IS NOT NULL THEN
            INSERT INTO public.member_roles (member_id, role_id, tenant_id)
            VALUES (new_member_id, owner_role_id, NEW.id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_tenant_created_assign_owner ON public.tenants;
CREATE TRIGGER on_tenant_created_assign_owner
    AFTER INSERT ON public.tenants
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_tenant_owner();

-- 6.5. Invitation Acceptance RPC (Enables invited users to join tenants securely)
CREATE OR REPLACE FUNCTION public.accept_invitation(p_token text)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_user_email TEXT;
    v_invitation RECORD;
    v_member_id UUID;
    v_token_hash TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to accept invitation';
    END IF;

    -- Fetch verified email from auth.users (single source of truth)
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;

    -- Compute SHA-256 hash of token to match token_hash
    v_token_hash := pg_catalog.encode(extensions.digest(p_token, 'sha256'), 'hex');

    SELECT * INTO v_invitation
    FROM public.tenant_invitations
    WHERE (token_hash = v_token_hash OR token_hash = p_token)
      AND status = 'pending'
      AND expires_at > timezone('utc'::text, now())
      AND lower(trim(email)) = lower(trim(v_user_email))
    FOR UPDATE;

    IF v_invitation.id IS NULL THEN
        RAISE EXCEPTION 'Invalid, expired, or unauthorized invitation token';
    END IF;

    -- Set session flag so enforce_rbac_owner_guards permits authorized role assignment
    PERFORM set_config('app.invitation_acceptance', 'true', true);

    INSERT INTO public.tenant_members (tenant_id, user_id, status)
    VALUES (v_invitation.tenant_id, v_user_id, 'active')
    ON CONFLICT (tenant_id, user_id) DO UPDATE SET status = 'active', updated_at = timezone('utc'::text, now())
    RETURNING id INTO v_member_id;

    IF v_invitation.role_id IS NOT NULL THEN
        INSERT INTO public.member_roles (member_id, role_id, tenant_id)
        VALUES (v_member_id, v_invitation.role_id, v_invitation.tenant_id)
        ON CONFLICT (member_id, role_id) DO NOTHING;
    END IF;

    UPDATE public.tenant_invitations
    SET status = 'accepted'
    WHERE id = v_invitation.id;

    RETURN jsonb_build_object(
        'success', true,
        'tenant_id', v_invitation.tenant_id,
        'member_id', v_member_id,
        'role_id', v_invitation.role_id
    );
END;
$$;

-- 6.6. RBAC Owner Tampering & Hostile Takeover Prevention Guard
CREATE OR REPLACE FUNCTION public.enforce_rbac_owner_guards()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_owner_role_id UUID;
    v_caller_is_owner BOOLEAN;
    v_remaining_owners INT;
    v_target_is_owner BOOLEAN;
    v_is_initial_tenant_owner BOOLEAN := false;
    v_is_invitation_acceptance BOOLEAN := false;
BEGIN
    SELECT id INTO v_owner_role_id FROM public.roles WHERE tenant_id IS NULL AND name = 'owner' LIMIT 1;

    -- Allow initial owner assignment when creating a brand new tenant
    IF TG_OP = 'INSERT' AND NEW.tenant_id IS NOT NULL THEN
        v_is_initial_tenant_owner := EXISTS (
            SELECT 1 FROM public.tenants t
            WHERE t.id = NEW.tenant_id
              AND t.created_by = auth.uid()
              AND NOT EXISTS (
                  SELECT 1 FROM public.member_roles mr
                  WHERE mr.tenant_id = NEW.tenant_id
                    AND mr.role_id = v_owner_role_id
              )
        );
    END IF;

    v_is_invitation_acceptance := (COALESCE(current_setting('app.invitation_acceptance', true), 'false') = 'true');

    -- Check if caller is authenticated owner or system/trigger internal bypass
    v_caller_is_owner := (
        (COALESCE(auth.jwt() ->> 'role', '') = 'service_role')
        OR (auth.uid() IS NULL)
        OR v_is_invitation_acceptance
        OR v_is_initial_tenant_owner
        OR EXISTS (
            SELECT 1 FROM public.member_roles mr
            JOIN public.tenant_members tm ON tm.id = mr.member_id
            WHERE tm.tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id)
              AND tm.user_id = auth.uid()
              AND mr.role_id = v_owner_role_id
        )
    );

    IF TG_TABLE_NAME = 'member_roles' THEN
        -- Prevent non-owners from granting owner role
        IF TG_OP = 'INSERT' AND NEW.role_id = v_owner_role_id THEN
            IF NOT COALESCE(v_caller_is_owner, false) THEN
                RAISE EXCEPTION 'Privilege Escalation Blocked: Only an existing owner can grant the owner role.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;

        -- Prevent revoking owner role if it is the last owner of active tenant
        IF TG_OP = 'DELETE' AND OLD.role_id = v_owner_role_id THEN
            -- If parent tenant itself is being deleted, permit cascade delete
            IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = OLD.tenant_id) THEN
                RETURN OLD;
            END IF;

            IF NOT COALESCE(v_caller_is_owner, false) THEN
                RAISE EXCEPTION 'Privilege Escalation Blocked: Only an owner can revoke the owner role.'
                    USING ERRCODE = '42501';
            END IF;

            SELECT count(1) INTO v_remaining_owners
            FROM public.member_roles
            WHERE tenant_id = OLD.tenant_id
              AND role_id = v_owner_role_id
              AND member_id <> OLD.member_id;

            IF v_remaining_owners = 0 AND EXISTS (SELECT 1 FROM public.tenants WHERE id = OLD.tenant_id) THEN
                RAISE EXCEPTION 'Orphaned Tenant Blocked: Cannot remove the last owner of a tenant. Transfer ownership first.'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        RETURN COALESCE(NEW, OLD);

    ELSIF TG_TABLE_NAME = 'tenant_members' THEN
        IF TG_OP = 'DELETE' THEN
            -- If parent tenant itself is being deleted, permit cascade delete
            IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = OLD.tenant_id) THEN
                RETURN OLD;
            END IF;

            SELECT EXISTS (
                SELECT 1 FROM public.member_roles
                WHERE member_id = OLD.id AND role_id = v_owner_role_id
            ) INTO v_target_is_owner;

            IF v_target_is_owner THEN
                IF NOT COALESCE(v_caller_is_owner, false) THEN
                    RAISE EXCEPTION 'Hostile Takeover Blocked: Only an owner can remove an owner from a tenant.'
                        USING ERRCODE = '42501';
                END IF;

                SELECT count(1) INTO v_remaining_owners
                FROM public.member_roles
                WHERE tenant_id = OLD.tenant_id
                  AND role_id = v_owner_role_id
                  AND member_id <> OLD.id;

                IF v_remaining_owners = 0 AND EXISTS (SELECT 1 FROM public.tenants WHERE id = OLD.tenant_id) THEN
                    RAISE EXCEPTION 'Orphaned Tenant Blocked: Cannot delete the last owner of a tenant.'
                        USING ERRCODE = '23514';
                END IF;
            END IF;
        END IF;
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_guard_member_roles ON public.member_roles;
CREATE TRIGGER trigger_guard_member_roles
    BEFORE INSERT OR DELETE ON public.member_roles
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rbac_owner_guards();

DROP TRIGGER IF EXISTS trigger_guard_tenant_members ON public.tenant_members;
CREATE TRIGGER trigger_guard_tenant_members
    BEFORE DELETE ON public.tenant_members
    FOR EACH ROW EXECUTE FUNCTION public.enforce_rbac_owner_guards();

-- 6.7. Cross-Tenant Role & Member Assignment Invariant Guard
CREATE OR REPLACE FUNCTION public.validate_member_role_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_member_tenant_id UUID;
    v_role_tenant_id UUID;
BEGIN
    SELECT tenant_id INTO v_member_tenant_id
    FROM public.tenant_members
    WHERE id = NEW.member_id;

    IF v_member_tenant_id IS NULL OR v_member_tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-Tenant Member Assignment Blocked: Member % does not belong to tenant %', NEW.member_id, NEW.tenant_id
            USING ERRCODE = '23503';
    END IF;

    SELECT tenant_id INTO v_role_tenant_id
    FROM public.roles
    WHERE id = NEW.role_id;

    IF v_role_tenant_id IS NOT NULL AND v_role_tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-Tenant Role Assignment Blocked: Role % belongs to tenant %, not %', NEW.role_id, v_role_tenant_id, NEW.tenant_id
            USING ERRCODE = '23503';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_member_role ON public.member_roles;
CREATE TRIGGER trigger_validate_member_role
    BEFORE INSERT OR UPDATE ON public.member_roles
    FOR EACH ROW EXECUTE FUNCTION public.validate_member_role_assignment();

-- 6.8. Tenant Invitation Validation Guard
CREATE OR REPLACE FUNCTION public.validate_tenant_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_owner_role_id UUID;
    v_role_tenant_id UUID;
    v_caller_is_owner BOOLEAN;
BEGIN
    SELECT id INTO v_owner_role_id FROM public.roles WHERE tenant_id IS NULL AND name = 'owner' LIMIT 1;

    SELECT tenant_id INTO v_role_tenant_id FROM public.roles WHERE id = NEW.role_id;
    IF v_role_tenant_id IS NOT NULL AND v_role_tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-Tenant Role Blocked: Role does not belong to tenant %', NEW.tenant_id
            USING ERRCODE = '23503';
    END IF;

    IF NEW.role_id = v_owner_role_id THEN
        v_caller_is_owner := (
            COALESCE(auth.jwt() ->> 'role', '') = 'service_role'
            OR auth.uid() IS NULL
            OR EXISTS (
                SELECT 1 FROM public.member_roles mr
                JOIN public.tenant_members tm ON tm.id = mr.member_id
                WHERE tm.tenant_id = NEW.tenant_id
                  AND tm.user_id = auth.uid()
                  AND mr.role_id = v_owner_role_id
            )
        );

        IF NOT COALESCE(v_caller_is_owner, false) THEN
            RAISE EXCEPTION 'Privilege Escalation Blocked: Only an existing owner can invite an owner.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.expires_at <= timezone('utc'::text, now()) THEN
        RAISE EXCEPTION 'Invalid Expiration: expires_at must be in the future.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_validate_invitation ON public.tenant_invitations;
CREATE TRIGGER trigger_validate_invitation
    BEFORE INSERT OR UPDATE ON public.tenant_invitations
    FOR EACH ROW EXECUTE FUNCTION public.validate_tenant_invitation();

-- 6.9. Protect Profile Email Spoofing
CREATE OR REPLACE FUNCTION public.protect_profile_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        IF auth.uid() IS NOT NULL AND COALESCE(auth.jwt() ->> 'role', '') <> 'service_role' THEN
            NEW.email := OLD.email;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_protect_profile_email ON public.profiles;
CREATE TRIGGER trigger_protect_profile_email
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.protect_profile_email();

-- ============================================================================
-- 7. BẬT VÀ THIẾT LẬP CHÍNH SÁCH BẢO MẬT (ROW LEVEL SECURITY - RLS)
-- ============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_plugins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles are readable by authenticated users"
    ON public.profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE TO authenticated
    USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Users can view tenants they belong to"
    ON public.tenants FOR SELECT TO authenticated
    USING (id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Authenticated users can create new tenants"
    ON public.tenants FOR INSERT TO authenticated
    WITH CHECK ((SELECT auth.uid()) = created_by);

CREATE POLICY "Tenant owners or admins can update tenant info"
    ON public.tenants FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(id, 'tenants:update'))
    WITH CHECK (public.has_tenant_permission(id, 'tenants:update'));

CREATE POLICY "Only tenant owners can delete tenant"
    ON public.tenants FOR DELETE TO authenticated
    USING (public.has_tenant_permission(id, 'tenants:delete'));

CREATE POLICY "Users can view system roles and their tenant roles"
    ON public.roles FOR SELECT TO authenticated
    USING (tenant_id IS NULL OR tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Tenant admins can manage custom roles"
    ON public.roles FOR ALL TO authenticated
    USING (tenant_id IS NOT NULL AND public.has_tenant_permission(tenant_id, 'roles:manage'))
    WITH CHECK (tenant_id IS NOT NULL AND public.has_tenant_permission(tenant_id, 'roles:manage'));

CREATE POLICY "Permissions dictionary is readable by authenticated users"
    ON public.permissions FOR SELECT TO authenticated USING (true);

CREATE POLICY "Role permissions are readable by authenticated users"
    ON public.role_permissions FOR SELECT TO authenticated USING (true);

CREATE POLICY "Tenant admins can manage role permissions for custom roles"
    ON public.role_permissions FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.roles r
            WHERE r.id = role_permissions.role_id
              AND r.tenant_id IS NOT NULL
              AND public.has_tenant_permission(r.tenant_id, 'roles:manage')
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.roles r
            WHERE r.id = role_permissions.role_id
              AND r.tenant_id IS NOT NULL
              AND public.has_tenant_permission(r.tenant_id, 'roles:manage')
        )
    );

CREATE POLICY "Members can view other members in the same tenant"
    ON public.tenant_members FOR SELECT TO authenticated
    USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can update membership status"
    ON public.tenant_members FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:update'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:update'));

CREATE POLICY "Admins or members themselves can remove membership"
    ON public.tenant_members FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:delete') OR user_id = (SELECT auth.uid()));

CREATE POLICY "Members can view roles assigned to members in the same tenant"
    ON public.member_roles FOR SELECT TO authenticated
    USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can assign or revoke member roles"
    ON public.member_roles FOR ALL TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:manage'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:manage'));

CREATE POLICY "Authorized members can view tenant invitations"
    ON public.tenant_invitations FOR SELECT TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can create invitations"
    ON public.tenant_invitations FOR INSERT TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can cancel invitations"
    ON public.tenant_invitations FOR UPDATE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:invite'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can delete invitations"
    ON public.tenant_invitations FOR DELETE TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can view audit logs"
    ON public.audit_logs FOR SELECT TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'audit:read'));

-- Chính sách RLS cho System Plugins (Chỉ service_role có quyền thay đổi catalog plugin hệ thống)
CREATE POLICY "system_plugins_select_all" ON public.system_plugins
    FOR SELECT TO authenticated
    USING (TRUE);

CREATE POLICY "system_plugins_manage_admin" ON public.system_plugins
    FOR ALL TO authenticated
    USING (COALESCE(auth.jwt() ->> 'role', '') = 'service_role');

-- ============================================================================
-- 8. SEED DATA MẪU (PERMISSIONS & DEFAULT SYSTEM ROLES & CORE REGISTRATION)
-- ============================================================================

INSERT INTO public.permissions (id, module, description) VALUES
    ('tenants:read',    'tenants', 'Xem thông tin tổ chức'),
    ('tenants:update',  'tenants', 'Cập nhật cấu hình và thông tin tổ chức'),
    ('tenants:delete',  'tenants', 'Xóa hoàn toàn tổ chức'),
    ('members:read',    'members', 'Xem danh sách thành viên trong tổ chức'),
    ('members:invite',  'members', 'Mời thành viên mới vào tổ chức'),
    ('members:update',  'members', 'Cập nhật trạng thái thành viên'),
    ('members:manage',  'members', 'Gán và thu hồi vai trò của thành viên'),
    ('members:delete',  'members', 'Xóa thành viên khỏi tổ chức'),
    ('roles:read',      'roles',   'Xem danh sách các vai trò và quyền hạn'),
    ('roles:manage',    'roles',   'Tạo, sửa và xóa các vai trò tùy chỉnh (Custom Roles)'),
    ('billing:read',    'billing', 'Xem thông tin gói cước và hóa đơn'),
    ('billing:manage',  'billing', 'Thay đổi phương thức thanh toán và nâng cấp gói'),
    ('audit:read',      'audit',   'Xem nhật ký kiểm toán hệ thống'),
    ('plugins:read',    'system',  'Xem danh mục plugin đã cài đặt và cấu hình'),
    ('plugins:manage',  'system',  'Cài đặt, nâng cấp hoặc gỡ bỏ các plugin hệ thống')
ON CONFLICT (id) DO UPDATE SET 
    description = EXCLUDED.description,
    module = EXCLUDED.module;

INSERT INTO public.roles (id, tenant_id, name, display_name, description, is_system) VALUES
    ('00000000-0000-0000-0000-000000000001', NULL, 'owner',  'Chủ sở hữu',    'Toàn quyền kiểm soát và chịu trách nhiệm pháp lý cao nhất đối với tổ chức', true),
    ('00000000-0000-0000-0000-000000000002', NULL, 'admin',  'Quản trị viên', 'Quản lý thành viên, tài nguyên và cấu hình hoạt động thường nhật', true),
    ('00000000-0000-0000-0000-000000000003', NULL, 'member', 'Thành viên',    'Cộng tác viên tiêu chuẩn, tạo và chỉnh sửa tài nguyên được phép', true),
    ('00000000-0000-0000-0000-000000000004', NULL, 'viewer', 'Người xem',     'Chỉ có quyền đọc dữ liệu, không được tạo mới hoặc chỉnh sửa', true)
ON CONFLICT (id) DO NOTHING;

-- Gán toàn bộ quyền cho vai trò Owner
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001'::uuid, p.id FROM public.permissions p
ON CONFLICT DO NOTHING;

-- Gán quyền cho vai trò Admin (trừ tenants:delete)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000002'::uuid, p.id FROM public.permissions p 
WHERE p.id NOT IN ('tenants:delete')
ON CONFLICT DO NOTHING;

-- Gán quyền cho vai trò Member
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000003', 'tenants:read'),
    ('00000000-0000-0000-0000-000000000003', 'members:read'),
    ('00000000-0000-0000-0000-000000000003', 'roles:read'),
    ('00000000-0000-0000-0000-000000000003', 'plugins:read')
ON CONFLICT DO NOTHING;

-- Gán quyền cho vai trò Viewer
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000004', 'tenants:read'),
    ('00000000-0000-0000-0000-000000000004', 'members:read'),
    ('00000000-0000-0000-0000-000000000004', 'roles:read')
ON CONFLICT DO NOTHING;

-- 8.5. Tự Động Đăng Ký Core IAM vào Bảng System Plugins (is_system = TRUE)
SELECT public.register_plugin(
    'core-iam',
    'Multi-Tenant IAM & RBAC Engine',
    '1.0.0',
    'public',
    ARRAY[]::TEXT[],
    'Base Core Identity, Multi-tenancy, and Role-Based Access Control Platform',
    TRUE, -- is_system = true (Bất biến, không thể gỡ bỏ)
    '{"type": "kernel", "layer": 0, "immutable": true}'::jsonb
);
