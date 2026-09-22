# Nghiên Cứu & Thiết Kế Kiến Trúc Multi-Tenant RBAC Trên Supabase

## 1. Tổng Quan & Đặt Vấn Đề

Khi xây dựng các hệ thống SaaS (Software-as-a-Service), Creator Platforms hoặc Enterprise Applications trên nền tảng **Supabase** (PostgreSQL-as-a-Service), hai yêu cầu cốt lõi luôn song hành là:
1. **Multi-tenancy (Đa người thuê/Đa tổ chức)**: Cô lập dữ liệu tuyệt đối giữa các tổ chức/workspace/team (`tenant_id`).
2. **RBAC (Role-Based Access Control - Kiểm soát truy cập dựa trên vai trò)**: Phân quyền linh hoạt, từ các vai trò mặc định (Owner, Admin, Member, Viewer) đến các vai trò tùy chỉnh (Custom Roles) theo từng Tenant ở cấp độ Enterprise.

Khách hàng và ứng dụng đòi hỏi hệ thống phải:
- **Bảo mật tuyệt đối ở tầng cơ sở dữ liệu** (không phụ thuộc hoàn toàn vào code backend/API).
- **Khả năng mở rộng (Scalability)**: Xử lý từ vài nghìn đến hàng triệu tenants mà không làm suy giảm hiệu năng truy vấn.
- **Tương thích hoàn hảo với Supabase Auth & Row Level Security (RLS)**: Tránh lỗi đệ quy RLS (RLS infinite recursion) và tình trạng Sequential Scan làm sập database.

---

## 2. So Sánh Các Mô Hình Multi-Tenancy Trong PostgreSQL & Supabase

Dựa trên các tài liệu chính thống từ **Supabase**, **AWS Multi-Tenant SaaS Patterns** và **PostgreSQL Architecture**, có 3 kiến trúc multi-tenancy chính:

| Tiêu Chí | Database-per-Tenant | Schema-per-Tenant | Row-Level Tenancy (Shared Table + RLS) |
| :--- | :--- | :--- | :--- |
| **Cơ chế cô lập** | Mỗi tenant 1 database riêng biệt | Mỗi tenant 1 PostgreSQL schema riêng biệt | Chung bảng, phân tách bằng cột `tenant_id` + Postgres RLS |
| **Mức độ cô lập dữ liệu** | Tuyệt đối (Physical isolation) | Tương đối cao (Namespace isolation) | Rất cao (Cryptographic & Engine-level Logical isolation) |
| **Chi phí vận hành** | Rất tốn kém (Nhiều DB instance, connection pool) | Tốn tài nguyên RAM của catalog cache khi vượt quá vài nghìn schema | Tối ưu chi phí nhất, sử dụng hiệu quả pool kết nối |
| **Khả năng Migration / DDL** | Cực kỳ phức tạp (Chạy migration N lần) | Phức tạp (Migration N schema, dễ timeout) | Đơn giản nhất (1 lần migration cho toàn hệ thống) |
| **Giới hạn quy mô (Scale limit)** | Bị giới hạn bởi số DB instance | Khoảng ~1,000 - 3,000 schema trước khi Postgres catalog bị chậm | **Vô hạn** (Hỗ trợ triệu tenants, dễ dàng kết hợp Table Partitioning) |
| **Độ phù hợp với Supabase** | Kém (Supabase quản lý theo từng project DB) | Trung bình (Khó tích hợp với Supabase Studio & Auto-generated APIs) | **Hoàn hảo** (Là mô hình chuẩn được Supabase khuyến nghị chính thức) |

> **Kết luận kiến trúc**: Mô hình **Row-Level Tenancy (Shared Database, Shared Schema)** kết hợp **PostgreSQL Row Level Security (RLS)** là lựa chọn chuẩn mực, tối ưu nhất để scale trên Supabase.

---

## 3. Kiến Trúc RBAC Có Khả Năng Mở Rộng Cao (Scalable Multi-Tenant RBAC)

Để hệ thống RBAC không chỉ hỗ trợ các vai trò tĩnh (cứng) mà còn mở rộng được cho khách hàng B2B/Enterprise tự tạo vai trò riêng, mô hình chuẩn **NIST RBAC** được mở rộng theo không gian Tenant như sau:

```
[Tenants] 
   │
   ├── (1:N) ── [Tenant Members] ── (N:M) ── [Roles] ── (N:M) ── [Permissions]
   │                    │
   │               (User 1:1 Profile)
   │                    │
   └── (1:N) ── [Tenant Resources (e.g. Projects, Content...)]
```

### 3.1. Các Thành Phần Trọng Tâm

1. **`auth.users` & `public.profiles`**:
   - `auth.users`: Do Supabase Auth quản lý nội bộ (lưu email, mật khẩu mã hóa, metadata).
   - `public.profiles`: Bảng mở rộng trong schema `public`, đồng bộ 1:1 qua Database Trigger.

2. **`public.tenants`**:
   - Đóng vai trò là ranh giới cô lập (Isolation Boundary) của mọi dữ liệu.
   - Định danh duy nhất bằng `id` (UUIDv4) và `slug` (cho subdomain hoặc vanity URL).

3. **`public.tenant_members`**:
   - Xác định người dùng nào là thành viên của Tenant nào, trạng thái tham gia (`active`, `suspended`).

4. **`public.roles` (Hỗ trợ cả Global Role & Custom Tenant Role)**:
   - Cột `tenant_id` có tính chất `NULLABLE`:
     - Nếu `tenant_id IS NULL`: Đây là **System Global Role** (mặc định cho tất cả tenant như `owner`, `admin`, `member`, `viewer`).
     - Nếu `tenant_id = '<uuid>'`: Đây là **Custom Role** do chính Tenant đó định nghĩa (ví dụ: `billing_auditor`, `content_creator`).
   - Ràng buộc duy nhất: `UNIQUE (tenant_id, name)` giúp mỗi tenant vừa kế thừa vai trò chung, vừa tự tạo vai trò riêng mà không xung đột.

5. **`public.permissions`**:
   - Lưu trữ danh sách quyền nguyên tử (Atomic Actions) theo format chuẩn `resource:action` (ví dụ: `tenants:update`, `members:invite`, `billing:manage`, `projects:create`, `projects:delete`).
   - Cố định ở cấp độ hệ thống để mã nguồn backend/frontend dễ dàng kiểm tra.

6. **`public.role_permissions`**:
   - Bảng liên kết nhiều - nhiều giữa `roles` và `permissions`.

7. **`public.member_roles`**:
   - Cho phép một thành viên trong Tenant sở hữu một hoặc nhiều vai trò đồng thời (Multiple Roles per Member), ví dụ: Vừa là `member`, vừa kiêm nhiệm `billing_manager`.
   - Có cột `tenant_id` phi chuẩn hóa (denormalized) để phục vụ việc đánh chỉ mục composite cực nhanh và prune partition.

8. **`public.tenant_invitations`**:
   - Quản lý lời mời tham gia tổ chức qua email, kèm token hash và thời hạn hết hạn.

9. **`public.audit_logs`**:
   - Ghi vết hành động bảo mật (Ai, làm gì, trên bản ghi nào, thời gian nào, IP nào) bắt buộc cho tiêu chuẩn bảo mật SOC2 / ISO 27001 của SaaS.

---

## 4. Giải Quyết Các Thách Thức Hiệu Năng Của Supabase RLS

Row Level Security là cơ chế mạnh mẽ nhưng nếu triển khai sai có thể gây sụt giảm hiệu năng nghiêm trọng khi dữ liệu lớn. Dưới đây là các kỹ thuật tối ưu hóa cốt lõi được áp dụng:

### 4.1. Tránh Lặp Đệ Quy RLS (RLS Infinite Recursion)
- **Vấn đề**: Khi viết policy cho bảng `tenant_members` kiểm tra xem người dùng có phải là `admin` không bằng cách `SELECT` từ chính `tenant_members`, PostgreSQL sẽ rơi vào vòng lặp kiểm tra RLS vô tận.
- **Giải pháp**: Sử dụng các hàm trợ năng (Helper Functions) với thuộc tính `SECURITY DEFINER` và `SET search_path = ''`:
  ```sql
  CREATE OR REPLACE FUNCTION public.has_tenant_permission(
      _tenant_id uuid,
      _permission_id text
  ) RETURNS boolean
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
  ```
  - `SECURITY DEFINER` giúp hàm thực thi dưới quyền của `postgres` (bỏ qua RLS trên các bảng tra cứu nội bộ).
  - `SET search_path = ''` ngăn chặn tấn công chiếm quyền (privilege escalation via search_path hijacking).
  - `STABLE` cho phép PostgreSQL query optimizer cache kết quả hàm trong suốt quá trình thực thi 1 câu lệnh SQL duy nhất, thay vì chạy lại hàm cho từng dòng được quét!

### 4.2. Kỹ Thuật Wrap `(SELECT auth.uid())`
- **Vấn đề**: Viết `WHERE user_id = auth.uid()` khiến Postgres gọi hàm `auth.uid()` N lần tương ứng với N hàng dữ liệu.
- **Giải pháp**: Viết `WHERE user_id = (SELECT auth.uid())` biến hàm thành Subplan độc lập, chỉ tính toán duy nhất 1 lần cho toàn bộ truy vấn (Tăng tốc từ 10x - 100x).

### 4.3. Chiến Lược Hai Tầng (Two-Tier Authorization: JWT Claims + DB Fallback)
Khi hệ thống đạt hàng triệu request:
- **Tầng 1 (Siêu tốc - O(1))**: Dùng Supabase **Custom Access Token (JWT) Hook** để nạp sẵn `tenant_id` và danh sách `roles` / `permissions` vào Claims của JWT. RLS đọc trực tiếp `(auth.jwt() ->> 'tenant_id')::uuid` mà không tốn một lượt quét đĩa nào.
- **Tầng 2 (Tươi mới tức thì - Exact State)**: Dùng các hàm `STABLE SECURITY DEFINER` ở DB cho các thao tác nhạy cảm (như chuyển tiền, đổi quyền chủ sở hữu, xóa tài khoản).

---

## 5. Chiến Lược Scale (Khả Năng Chịu Tải Cao)

1. **Composite Primary Keys & Indexing**:
   - Tất cả các bảng tài nguyên đều đánh chỉ mục composite `(tenant_id, created_at DESC)` hoặc `(tenant_id, id)`.
   - Giúp mọi truy vấn đều sử dụng **Index Seek / Index Only Scan**, ngăn chặn tuyệt đối việc dò tìm chéo giữa các tenant.
2. **PostgreSQL Declarative Partitioning (Sẵn sàng phân vùng)**:
   - Bằng cách luôn đặt `tenant_id` trong Primary Key của các bảng dữ liệu lớn (như `audit_logs`, `events`, `posts`), khi số lượng bản ghi đạt hàng trăm triệu dòng, ta có thể dễ dàng chuyển sang `PARTITION BY HASH (tenant_id)` hoặc `PARTITION BY LIST (tenant_id)` mà không làm thay đổi logic ứng dụng.
3. **Connection Pooling**:
   - Sử dụng Supabase Supavisor / PgBouncer ở chế độ Transaction Pooling để quản lý hàng chục ngàn kết nối đồng thời từ Serverless / Edge Functions.
