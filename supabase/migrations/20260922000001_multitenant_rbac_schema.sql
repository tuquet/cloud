-- ============================================================================
-- SUPABASE MIGRATION: SCALABLE MULTI-TENANT RBAC DATABASE SCHEMA
-- Version: 20260922000001
-- Description: Production-ready Multi-tenant Role-Based Access Control schema
--              with RLS optimization, Custom Claims Hook support, and Seed Data.
-- ============================================================================

-- Bật phần mở rộng cần thiết
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

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

-- ============================================================================
-- 2. ĐỊNH NGHĨA CÁC BẢNG (TABLE DEFINITIONS)
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

-- Đảm bảo tên vai trò là duy nhất trong mỗi tenant, hoặc trong phạm vi system roles
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_tenant_name_unique 
    ON public.roles (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), name);

-- 2.4. Bảng Quyền hạn nguyên tử (Permissions)
CREATE TABLE IF NOT EXISTS public.permissions (
    id VARCHAR(64) PRIMARY KEY, -- Format: 'module:action' (vd: 'projects:create')
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
-- Hỗ trợ 1 thành viên có nhiều vai trò (Multi-role). Bao gồm cột tenant_id để tối ưu hóa Index & Partitioning.
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

-- 2.9. Bảng Nhật ký kiểm toán an ninh (Audit Logs - Sẵn sàng Partition theo tenant_id)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2.10. Bảng Dữ liệu mẫu thuộc Tenant (Demo Resource: Projects)
CREATE TABLE IF NOT EXISTS public.projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ============================================================================
-- 3. CHỈ MỤC HIỆU NĂNG CAO (SCALABLE COMPOSITE INDEXES)
-- ============================================================================

-- Profiles
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- Tenants
CREATE INDEX IF NOT EXISTS idx_tenants_status ON public.tenants(status);
CREATE INDEX IF NOT EXISTS idx_tenants_created_by ON public.tenants(created_by);

-- Roles
CREATE INDEX IF NOT EXISTS idx_roles_tenant_id ON public.roles(tenant_id);

-- Tenant Members (Cực kỳ quan trọng khi quy mô tăng cao)
CREATE INDEX IF NOT EXISTS idx_tenant_members_user_status ON public.tenant_members(user_id, status);
CREATE INDEX IF NOT EXISTS idx_tenant_members_tenant_user ON public.tenant_members(tenant_id, user_id);

-- Member Roles
CREATE INDEX IF NOT EXISTS idx_member_roles_role_id ON public.member_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_member_roles_tenant_id ON public.member_roles(tenant_id);

-- Tenant Invitations
CREATE INDEX IF NOT EXISTS idx_invitations_tenant_status ON public.tenant_invitations(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_invitations_email ON public.tenant_invitations(email);

-- Audit Logs (Tối ưu hóa tìm kiếm log theo tenant và thời gian)
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_time ON public.audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(tenant_id, actor_id);

-- Projects (Composite index cho Tenant isolation)
CREATE INDEX IF NOT EXISTS idx_projects_tenant_created ON public.projects(tenant_id, created_at DESC);

-- ============================================================================
-- 4. HÀM TRỢ NĂNG BẢO MẬT & TRÁNH ĐỆ QUY RLS (SECURITY DEFINER HELPERS)
-- ============================================================================

-- 4.1. Lấy danh sách ID các tenant mà user hiện tại đang tham gia và hoạt động
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

-- 4.2. Kiểm tra xem người dùng hiện tại có phải thành viên active của tenant không
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

-- 4.3. Kiểm tra xem người dùng có sở hữu quyền cụ thể (permission) trong tenant không
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

-- 4.4. Kiểm tra nhanh xem người dùng có phải là Owner hoặc Admin của tenant không
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

-- 4.5. Auth Hook: Tự động gắn Tenant ID và Roles vào Supabase JWT Access Token
-- Giúp RLS đọc siêu tốc từ JWT Claims O(1) mà không cần query lại database
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
    -- Lấy danh sách tenant và roles của user
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
    FROM public.tenant_members tm
    WHERE tm.user_id = (event->>'user_id')::uuid
      AND tm.status = 'active';

    claims := event->'claims';
    claims := jsonb_set(claims, '{app_metadata,tenants}', user_tenants);
    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

-- ============================================================================
-- 5. DATABASE TRIGGERS TỰ ĐỘNG HÓA
-- ============================================================================

-- 5.1. Tự động cập nhật `updated_at`
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
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

DROP TRIGGER IF EXISTS set_projects_updated_at ON public.projects;
CREATE TRIGGER set_projects_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 5.2. Đồng bộ tự động từ auth.users sang public.profiles khi có đăng ký mới
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

-- 5.3. Tự động thêm người tạo Tenant làm thành viên với vai trò 'owner'
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
        -- Tìm System Role 'owner'
        SELECT id INTO owner_role_id
        FROM public.roles
        WHERE tenant_id IS NULL AND name = 'owner'
        LIMIT 1;

        -- Tạo bản ghi thành viên
        INSERT INTO public.tenant_members (tenant_id, user_id, status)
        VALUES (NEW.id, NEW.created_by, 'active')
        RETURNING id INTO new_member_id;

        -- Gán vai trò Owner
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

-- ============================================================================
-- 6. BẬT VÀ THIẾT LẬP CHÍNH SÁCH BẢO MẬT (ROW LEVEL SECURITY - RLS)
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
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 6.1. Policies cho PROFILES
-- ----------------------------------------------------------------------------
CREATE POLICY "Profiles are readable by authenticated users"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK ((SELECT auth.uid()) = id);

-- ----------------------------------------------------------------------------
-- 6.2. Policies cho TENANTS
-- ----------------------------------------------------------------------------
CREATE POLICY "Users can view tenants they belong to"
    ON public.tenants FOR SELECT
    TO authenticated
    USING (id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Authenticated users can create new tenants"
    ON public.tenants FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = created_by);

CREATE POLICY "Tenant owners or admins can update tenant info"
    ON public.tenants FOR UPDATE
    TO authenticated
    USING (public.has_tenant_permission(id, 'tenants:update'))
    WITH CHECK (public.has_tenant_permission(id, 'tenants:update'));

CREATE POLICY "Only tenant owners can delete tenant"
    ON public.tenants FOR DELETE
    TO authenticated
    USING (public.has_tenant_permission(id, 'tenants:delete'));

-- ----------------------------------------------------------------------------
-- 6.3. Policies cho ROLES & PERMISSIONS
-- ----------------------------------------------------------------------------
CREATE POLICY "Users can view system roles and their tenant roles"
    ON public.roles FOR SELECT
    TO authenticated
    USING (tenant_id IS NULL OR tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Tenant admins can manage custom roles"
    ON public.roles FOR ALL
    TO authenticated
    USING (tenant_id IS NOT NULL AND public.has_tenant_permission(tenant_id, 'roles:manage'))
    WITH CHECK (tenant_id IS NOT NULL AND public.has_tenant_permission(tenant_id, 'roles:manage'));

CREATE POLICY "Permissions dictionary is readable by authenticated users"
    ON public.permissions FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Role permissions are readable by authenticated users"
    ON public.role_permissions FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Tenant admins can manage role permissions for custom roles"
    ON public.role_permissions FOR ALL
    TO authenticated
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

-- ----------------------------------------------------------------------------
-- 6.4. Policies cho TENANT_MEMBERS & MEMBER_ROLES
-- ----------------------------------------------------------------------------
CREATE POLICY "Members can view other members in the same tenant"
    ON public.tenant_members FOR SELECT
    TO authenticated
    USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can update membership status"
    ON public.tenant_members FOR UPDATE
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:update'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:update'));

CREATE POLICY "Admins can remove members"
    ON public.tenant_members FOR DELETE
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:delete'));

CREATE POLICY "Members can view roles assigned to members in the same tenant"
    ON public.member_roles FOR SELECT
    TO authenticated
    USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can assign or revoke member roles"
    ON public.member_roles FOR ALL
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:manage'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:manage'));

-- ----------------------------------------------------------------------------
-- 6.5. Policies cho INVITATIONS & AUDIT LOGS
-- ----------------------------------------------------------------------------
CREATE POLICY "Authorized members can view tenant invitations"
    ON public.tenant_invitations FOR SELECT
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can create invitations"
    ON public.tenant_invitations FOR INSERT
    TO authenticated
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can cancel invitations"
    ON public.tenant_invitations FOR UPDATE
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'members:invite'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'members:invite'));

CREATE POLICY "Authorized members can view audit logs"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'audit:read'));

-- ----------------------------------------------------------------------------
-- 6.6. Policies cho Dữ Liệu Nghiệp Vụ (PROJECTS - Tài nguyên theo Tenant)
-- ----------------------------------------------------------------------------
CREATE POLICY "Tenant members can view projects"
    ON public.projects FOR SELECT
    TO authenticated
    USING (
        tenant_id IN (SELECT public.get_user_tenant_ids()) 
        AND public.has_tenant_permission(tenant_id, 'projects:read')
    );

CREATE POLICY "Tenant members with create permission can insert projects"
    ON public.projects FOR INSERT
    TO authenticated
    WITH CHECK (
        tenant_id IN (SELECT public.get_user_tenant_ids()) 
        AND public.has_tenant_permission(tenant_id, 'projects:create')
    );

CREATE POLICY "Tenant members with update permission can edit projects"
    ON public.projects FOR UPDATE
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'projects:update'))
    WITH CHECK (public.has_tenant_permission(tenant_id, 'projects:update'));

CREATE POLICY "Tenant members with delete permission can delete projects"
    ON public.projects FOR DELETE
    TO authenticated
    USING (public.has_tenant_permission(tenant_id, 'projects:delete'));

-- ============================================================================
-- 7. SEED DATA MẪU (PERMISSIONS & DEFAULT SYSTEM ROLES)
-- ============================================================================

-- 7.1. Chèn danh mục Quyền hạn nguyên tử (Permissions)
INSERT INTO public.permissions (id, module, description) VALUES
    -- Tenant module
    ('tenants:read', 'tenants', 'Xem thông tin tổ chức'),
    ('tenants:update', 'tenants', 'Cập nhật cấu hình và thông tin tổ chức'),
    ('tenants:delete', 'tenants', 'Xóa hoàn toàn tổ chức'),
    
    -- Members module
    ('members:read', 'members', 'Xem danh sách thành viên trong tổ chức'),
    ('members:invite', 'members', 'Mời thành viên mới vào tổ chức'),
    ('members:update', 'members', 'Cập nhật trạng thái thành viên'),
    ('members:manage', 'members', 'Gán và thu hồi vai trò của thành viên'),
    ('members:delete', 'members', 'Xóa thành viên khỏi tổ chức'),

    -- Roles module
    ('roles:read', 'roles', 'Xem danh sách các vai trò và quyền hạn'),
    ('roles:manage', 'roles', 'Tạo, sửa và xóa các vai trò tùy chỉnh (Custom Roles)'),

    -- Billing module
    ('billing:read', 'billing', 'Xem thông tin gói cước và hóa đơn'),
    ('billing:manage', 'billing', 'Thay đổi phương thức thanh toán và nâng cấp gói'),

    -- Audit module
    ('audit:read', 'audit', 'Xem nhật ký kiểm toán hệ thống'),

    -- Projects (Business Resource) module
    ('projects:read', 'projects', 'Xem danh sách và chi tiết dự án'),
    ('projects:create', 'projects', 'Tạo dự án mới'),
    ('projects:update', 'projects', 'Chỉnh sửa nội dung dự án'),
    ('projects:delete', 'projects', 'Xóa bỏ dự án')
ON CONFLICT (id) DO UPDATE SET 
    description = EXCLUDED.description,
    module = EXCLUDED.module;

-- 7.2. Chèn các Vai trò Hệ thống mặc định (System Roles: tenant_id IS NULL)
INSERT INTO public.roles (id, tenant_id, name, display_name, description, is_system) VALUES
    ('00000000-0000-0000-0000-000000000001', NULL, 'owner', 'Chủ sở hữu', 'Toàn quyền kiểm soát và chịu trách nhiệm pháp lý cao nhất đối với tổ chức', true),
    ('00000000-0000-0000-0000-000000000002', NULL, 'admin', 'Quản trị viên', 'Quản lý thành viên, tài nguyên và cấu hình hoạt động thường nhật', true),
    ('00000000-0000-0000-0000-000000000003', NULL, 'member', 'Thành viên', 'Cộng tác viên tiêu chuẩn, tạo và chỉnh sửa tài nguyên được phép', true),
    ('00000000-0000-0000-0000-000000000004', NULL, 'viewer', 'Người xem', 'Chỉ có quyền đọc dữ liệu, không được tạo mới hoặc chỉnh sửa', true)
ON CONFLICT (id) DO NOTHING;

-- 7.3. Gán Quyền tương ứng cho các System Roles (Role Permissions Mapping)

-- (A) Owner: Sở hữu TẤT CẢ các quyền hiện có
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001'::uuid, p.id
FROM public.permissions p
ON CONFLICT DO NOTHING;

-- (B) Admin: Có hầu hết các quyền, ngoại trừ xóa vĩnh viễn tổ chức
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000002'::uuid, p.id
FROM public.permissions p
WHERE p.id NOT IN ('tenants:delete')
ON CONFLICT DO NOTHING;

-- (C) Member: Đọc và tương tác với tài nguyên dự án, xem danh sách thành viên
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000003', 'tenants:read'),
    ('00000000-0000-0000-0000-000000000003', 'members:read'),
    ('00000000-0000-0000-0000-000000000003', 'roles:read'),
    ('00000000-0000-0000-0000-000000000003', 'projects:read'),
    ('00000000-0000-0000-0000-000000000003', 'projects:create'),
    ('00000000-0000-0000-0000-000000000003', 'projects:update')
ON CONFLICT DO NOTHING;

-- (D) Viewer: Quyền chỉ đọc (Read-only)
INSERT INTO public.role_permissions (role_id, permission_id) VALUES
    ('00000000-0000-0000-0000-000000000004', 'tenants:read'),
    ('00000000-0000-0000-0000-000000000004', 'members:read'),
    ('00000000-0000-0000-0000-000000000004', 'roles:read'),
    ('00000000-0000-0000-0000-000000000004', 'projects:read')
ON CONFLICT DO NOTHING;
