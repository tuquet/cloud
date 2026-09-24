# 🛡️ System Component: Multi-Tenant IAM & RBAC Engine (`core-iam`)

## 1. Tổng Quan
`core-iam` là phân hệ **Nền tảng Cốt lõi (Base Core / Kernel)** của `tuquet-cloud`. Phân hệ này chịu trách nhiệm thiết lập ranh giới đa tổ chức (Multi-tenant Boundary), mô hình kiểm soát truy cập dựa trên vai trò (RBAC), nhật ký an ninh (Audit Logs), và động cơ quản lý vòng đời plugin (`system_plugins`).

* **Trạng thái:** `is_system = true` (Thành phần bất biến, cấm gỡ bỏ để bảo vệ toàn vẹn hệ thống).
* **Schema:** `public`.
* **Khởi tạo tự động:** Được nạp trực tiếp qua Supabase migration `supabase/migrations/20260920000001_base_platform_core.sql`.

## 2. Các Bảng Cốt Lõi (Core Tables)
1. `public.profiles`: Hồ sơ người dùng mở rộng (1:1 với `auth.users`).
2. `public.tenants`: Ranh giới tổ chức / workspace (Tenant Boundary).
3. `public.roles`: Danh mục vai trò (System Roles + Custom Tenant Roles).
4. `public.permissions`: Từ điển quyền hạn nguyên tử (`module:action`).
5. `public.role_permissions`: Bảng liên kết Phân quyền <-> Vai trò.
6. `public.tenant_members`: Quan hệ Người dùng tham gia Tổ chức.
7. `public.member_roles`: Gán Vai trò cho Thành viên.
8. `public.tenant_invitations`: Lời mời tham gia tổ chức qua mã token hash.
9. `public.audit_logs`: Nhật ký kiểm toán an ninh với `BIGINT GENERATED ALWAYS AS IDENTITY`.
10. `public.system_plugins`: Bảng đăng ký và điều phối vòng đời của toàn bộ các plugin trong hệ thống.

## 3. Các Hàm Trợ Năng An Ninh (Security Definer Helpers)
- `public.get_user_tenant_ids()`: Lấy danh sách tenant IDs mà người dùng hiện tại đang tham gia (active).
- `public.is_tenant_member(_tenant_id)`: Kiểm tra tư cách thành viên tenant.
- `public.has_tenant_permission(_tenant_id, _permission_id)`: Kiểm tra quyền hạn nguyên tử trong tenant.
- `public.is_tenant_admin(_tenant_id)`: Kiểm tra tư cách Owner/Admin của tenant.
- `public.custom_access_token_hook(event)`: Hook tự động nhúng danh sách tenant và vai trò vào JWT claims, giới hạn an toàn 25 tenants (<8KB Header).

## 4. Kiểm Toán Toàn Vẹn (Health Inspection)
Thực thi tệp `inspect.sql` để kiểm tra độ tin cậy và sự sẵn sàng của Core IAM.
