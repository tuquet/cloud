-- ============================================================================
-- TUQUET-CLOUD COMPONENT: CORE IAM HEALTH & INTEGRITY INSPECTION
-- Purpose: Verify foundational tables, RLS enablement, and system plugin status
-- ============================================================================

-- 1. Check all Core Tables and RLS Status
SELECT 
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public' 
  AND tablename IN (
      'profiles', 'tenants', 'roles', 'permissions', 'role_permissions',
      'tenant_members', 'member_roles', 'tenant_invitations', 'audit_logs', 'system_plugins'
  )
ORDER BY tablename ASC;

-- 2. Verify System Plugin Registry Status
SELECT 
    id,
    name,
    version,
    schema_name,
    status,
    is_system,
    installed_at
FROM public.system_plugins
WHERE id = 'core-iam';

-- 3. Verify Default Roles & Permissions Count
SELECT 
    r.name AS role_name,
    r.is_system,
    count(rp.permission_id) AS total_permissions
FROM public.roles r
LEFT JOIN public.role_permissions rp ON rp.role_id = r.id
WHERE r.tenant_id IS NULL
GROUP BY r.name, r.is_system
ORDER BY total_permissions DESC;
