# Từ Điển Thuật Ngữ & Chuẩn Hóa Danh Pháp (Terminology Dictionary & Anti-Hallucination Lexicon)

> **Mục Đích Tối Thượng**: Tài liệu này đóng vai trò là **Hiến pháp thuật ngữ duy nhất (Single Source of Truth)** của hệ thống `tuquet-cloud` và toàn bộ hệ sinh thái Omniverse Creator (`tuquet-lib`, `tuquet-automa`, `tuquet-cloud`, `tuquet-scoop-bucket`).  
> Mọi tài liệu kỹ thuật, mã nguồn SQL, migration, API DTO, mã nguồn Frontend và AI Agents **bắt buộc tuân thủ 100%**, triệt tiêu hoàn toàn hiện tượng **ảo giác thuật ngữ (Terminology Hallucination)** hoặc dùng lẫn lộn giữa các khái niệm.

---

## 1. Năm Nguyên Tắc Bất Biến Về Thuật Ngữ (5 Golden Rules)

1. **Một Khái Niệm - Một Định Danh Duy Nhất**: Mỗi thực thể kỹ thuật chỉ có duy nhất một danh pháp chuẩn trong cơ sở dữ liệu và tài liệu. Tuyệt đối không dùng nhiều từ đồng nghĩa để chỉ cùng một bảng hay một trường.
2. **Cấm Dùng Thuật Ngữ Cấm (Zero Forbidden Terms)**: Các từ ngữ dễ gây nhầm lẫn đã được liệt kê trong bảng cấm (Forbidden Terms) không bao giờ được xuất hiện trong schema, code API hoặc tài liệu kiến trúc.
3. **Phân Định Rõ Ranh Giới Giữa Thực Thể DB và Nhãn Giao Diện (Data vs UI)**: Tên thực thể database (`tenants`, `profiles`, `runners`) là bất biến; các nhãn hiển thị người dùng (như "Workspace", "Hồ sơ", "Máy trạm") chỉ là lớp trình diễn (UI Presentation Layer) và phải luôn mở ngoặc chú thích rõ thực thể gốc khi viết docs kỹ thuật.
4. **Quy Chuẩn Cấu Trúc Khóa & Schema Minh Bạch**: 
   - PostgreSQL Schemas: chữ thường `snake_case` đơn số (`public`, `media`, `billing`, `events`, `automa`).
   - PostgreSQL Tables: danh từ số nhiều `snake_case` (`tenants`, `profiles`, `roles`, `permissions`, `assets`, `plans`, `workflows`, `runners`).
   - Cột khóa chính: luôn là `id`. Cột khóa ngoại trỏ tới bảng `<table>`: luôn là `<table>_id` (vd: `tenant_id`, `user_id`, `role_id`, `workflow_id`).
5. **Định Dạng Quyền Hạn Nguyên Tử Chuẩn**: Toàn bộ mã quyền hạn (`permission_id`) phải tuân thủ nghiêm ngặt cú pháp 3 cấp: `<module>:<resource>:<action>` (vd: `automa:campaigns:run`, `media:assets:upload`, `billing:plans:view`).

---

## 2. Bảng Tra Cứu Đối Chiếu Chuẩn (Canonical Lexicon Matrix)

Bảng tổng hợp nhanh dùng để đối soát chống ảo giác khi viết docs hoặc lập trình:

| Thuật Ngữ Chuẩn (Canonical Term) | Schema & Bảng Database | Thuật Ngữ BỊ CẤM / DỄ GÂY ẢO GIÁC (Forbidden / Ambiguous) | Ranh Giới Trách Nhiệm & Bất Biến Kỹ Thuật |
| :--- | :--- | :--- | :--- |
| **`Tenant`** | `public.tenants` | ❌ *Organization*, *Workspace*, *Account*, *Team*, *Project* | Ranh giới cô lập dữ liệu tối cao của đa khách hàng (Multi-Tenancy Isolation Boundary). Mọi bảng con đều mang `tenant_id`. |
| **`User`** | `auth.users` | ❌ *Account*, *Person*, *Client* | Thực thể định danh do Supabase Auth quản lý (email, password hash, OAuth provider). |
| **`Profile`** | `public.profiles` | ❌ *User Metadata*, *Account Info*, *Browser Profile* | Bản ghi mở rộng trong schema `public`, đồng bộ 1:1 với `auth.users` qua database trigger. |
| **`Tenant Member`** | `public.tenant_members` | ❌ *User*, *Profile*, *Employee*, *Team Member* | Quan hệ thành viên liên kết giữa 1 `Profile` và 1 `Tenant`, kèm trạng thái (`active`/`suspended`). |
| **`Role`** | `public.roles` | ❌ *Group*, *Tier*, *Level*, *Permission Set* | Tập hợp danh mục vai trò (`owner`, `admin`, `member`, `viewer` hoặc Custom Roles). |
| **`Permission`** | `public.permissions` | ❌ *Right*, *Privilege*, *Capability*, *Scope* | Chuỗi quyền nguyên tử dạng `<module>:<resource>:<action>` (vd: `tenants:update`). |
| **`Member Role`** | `public.member_roles` | ❌ *User Role*, *Role Assignment* | Bảng ánh xạ gán vai trò `role_id` cho thành viên `member_id` trong một `tenant_id`. |
| **`Plugin`** | `public.system_plugins` | ❌ *Module*, *Extension*, *Addon*, *Package* | Gói tính năng tự trị trong database có thư mục `supabase/plugins/<id>/` và Postgres Schema riêng. |
| **`Storage`** | `media.assets` & `tenant-assets` | ❌ *Vault*, *Media Bucket*, *File Drive* | Dịch vụ lưu trữ tệp đa phương tiện của cloud. Từ "Vault" bị CẤM trong cloud. |
| **`Browser`** | `automa.runners` / `*.browser.json` | ❌ *Profile*, *Browser Profile*, *Anti-detect Profile* | Thực thể trình duyệt ảo độc lập trong hệ sinh thái Automa. Tuyệt đối KHÔNG gọi là "Profile". |
| **`Runner`** | `automa.runners` | ❌ *Worker*, *Agent Node*, *Bot*, *Client Daemon* | Nút máy trạm thực thi kịch bản (máy tính cá nhân hoặc Cloud VPS chạy Axum daemon). |
| **`Workflow`** | `automa.workflows` | ❌ *Script*, *Flowchart*, *Automation Pipeline* | Quy trình tự động hóa đồ thị trực quan (Node Graph JSON tương thích VueFlow). |
| **`Campaign Run`** | `automa.campaign_runs` | ❌ *Batch Job*, *Execution*, *Run Task* | Phiên thực thi chiến dịch chạy kịch bản trên cụm runner phân tán. |
| **`Execution Log`** | `automa.execution_logs` | ❌ *Audit Log*, *System Log*, *Trace File* | Nhật ký luồng dữ liệu vi mô (block telemetry) trong suốt quá trình chạy kịch bản. |
| **`Transactional Outbox`**| `events.outbox` | ❌ *Message Queue*, *Kafka Stream*, *RabbitMQ* | Hàng đợi sự kiện an toàn giao dịch ACID trong PostgreSQL phục vụ phát tán Webhook. |
| **`Usage Meter`** | `billing.usage_meters` | ❌ *Quota Counter*, *Metric Tracker* | Đồng hồ đo lường mức độ tiêu thụ tài nguyên thực tế theo chu kỳ thanh toán. |

---

## 3. Chi Tiết Từng Phân Vùng Nghiệp Vụ

### 3.1. Phân Vùng Định Danh & Phân Quyền Đa Tổ Chức (Identity & Multi-Tenant IAM)

```
[auth.users] (Supabase Auth)
     │ (Trigger 1:1 đồng bộ)
     ▼
[public.profiles] ◄──────┐
     │                   │
     │ gia nhập          │ tạo ra
     ▼                   │
[public.tenant_members] ─┴──► [public.tenants] (Ranh giới cô lập tối cao)
     │                             │
     │ được gán                    │ sở hữu
     ▼                             ▼
[public.member_roles] ◄────── [public.roles]
                                   │
                                   │ sở hữu
                                   ▼
                             [public.role_permissions] ◄── [public.permissions]
```

#### Định Nghĩa Chi Tiết & Quy Tắc Tránh Ảo Giác:
1. **`Tenant` (Bảng `public.tenants`)**:
   - **Định nghĩa**: Là đơn vị tổ chức, workspace hoặc công ty thuê dịch vụ phần mềm. Là ranh giới phân tách dữ liệu cứng (Security Boundary).
   - **Ảo giác thường gặp**: Tự ý gọi bảng là `workspaces`, `organizations`, `accounts` hoặc `projects`.
   - **Quy tắc**: Trong code SQL, API DTO, SDK luôn dùng `tenant_id UUID`. Không bao giờ tạo bảng `workspaces` hay `projects` thay thế.
2. **`User` vs `Profile`**:
   - **`User` (`auth.users`)**: Do hệ thống Supabase Auth nội bộ kiểm soát. Chứa mật khẩu băm, email đăng nhập, token xác thực. Mã nguồn ứng dụng KHÔNG can thiệp trực tiếp vào schema `auth`.
   - **`Profile` (`public.profiles`)**: Thực thể người dùng trong schema `public`. Đồng bộ 1:1 với `auth.users.id`. Chứa các thông tin mở rộng: `full_name`, `avatar_url`, `updated_at`.
   - **Quy tắc**: Khi viết truy vấn nghiệp vụ hoặc liên kết người dùng, luôn trỏ khóa ngoại `created_by` hoặc `user_id` tới `public.profiles(id)`.
3. **`Tenant Member` (Bảng `public.tenant_members`)**:
   - **Định nghĩa**: Bản ghi thể hiện người dùng tham gia vào một Tenant. Một người dùng có thể là thành viên của nhiều Tenant khác nhau với các trạng thái (`active`, `suspended`).
   - **Ảo giác thường gặp**: Đồng nhất Member với User.
   - **Quy tắc**: Khi xóa một User, toàn bộ bản ghi `tenant_members` liên quan bị xóa theo (`CASCADE`), nhưng bản thân Tenant vẫn tồn tại.
4. **`Role` vs `Permission`**:
   - **`Role` (`public.roles`)**: Vai trò đóng gói (vd: `owner`, `admin`, `member`, `viewer`). Hỗ trợ 2 loại:
     - **System Role**: Toàn cục hệ thống, có `tenant_id IS NULL` và `is_system = true`.
     - **Custom Tenant Role**: Do từng Tenant tự định nghĩa, có `tenant_id NOT NULL` và `is_system = false`.
   - **`Permission` (`public.permissions`)**: Quyền nguyên tử độc lập (Atomic Capability). Chuẩn hóa dưới dạng `<module>:<resource>:<action>` (vd: `automa:runners:manage`).
   - **Quy tắc**: Quyền không bao giờ được gán trực tiếp cho Member. Quyền gán cho Role qua `public.role_permissions`, và Role gán cho Member qua `public.member_roles`.
5. **`Custom Access Token Hook` (Hàm `public.custom_access_token_hook`)**:
   - **Định nghĩa**: Hàm Postgres được Supabase Auth kích hoạt mỗi khi sinh JWT cho người dùng.
   - **Chức năng**: Tự động truy vấn `tenant_id` đang hoạt động, gom danh sách `roles` và tối đa **25 quyền** `permissions` tiêm vào `app_metadata` của JWT.
   - **Quy tắc**: Giúp Row Level Security (RLS) đạt hiệu năng **$O(1)$** mà không gây hiện tượng RLS Infinite Recursion.
6. **`Audit Log` (Bảng `public.audit_logs`)**:
   - **Định nghĩa**: Nhật ký an ninh tuần tự ghi vết mọi hành vi thay đổi cấu hình, phân quyền, thêm/xóa thành viên.
   - **Quy tắc**: Khóa chính là `BIGINT GENERATED ALWAYS AS IDENTITY`, lưu địa chỉ IP kiểu `INET`, trường `tenant_id` phục vụ việc phân mảnh dữ liệu (Table Partitioning) sau này.

---

### 3.2. Phân Vùng Hệ Sinh Thái Plugin (Plugin System Architecture)

```
[public.system_plugins] (Bảng Registry Quản Lý Trung Tâm)
        │
        ├── 'core-iam'       ──► Schema: public    (Kernel Bất biến: is_system = true)
        ├── 'storage'        ──► Schema: media     (On-demand Plugin)
        ├── 'subscriptions'  ──► Schema: billing   (On-demand Plugin)
        ├── 'webhooks'       ──► Schema: events    (On-demand Plugin)
        └── 'automa'         ──► Schema: automa    (On-demand Plugin)
```

#### Định Nghĩa Chi Tiết & Quy Tắc Tránh Ảo Giác:
1. **`Plugin` (Thực thể `public.system_plugins`)**:
   - **Định nghĩa**: Gói tính năng cơ sở dữ liệu độc lập, tự trị, có thể cài đặt hoặc gỡ bỏ mà không làm ảnh hưởng đến Base Core.
   - **Ảo giác thường gặp**: Gọi là "Extension", "Module", "Package", "Addon".
   - **Quy tắc**: Từ khóa thống nhất là **`Plugin`**. Mỗi plugin có một định danh chữ thường độc nhất (`id`), ví dụ: `automa`, `storage`, `subscriptions`, `webhooks`.
2. **Cấu Trúc Tệp Chuẩn Của Một Plugin**:
   Mỗi plugin trong `supabase/plugins/<plugin_id>/` bắt buộc phải có đủ 4 thành phần chuẩn mực:
   - `plugin.json`: Tệp manifest khai báo `id`, `name`, `version`, `schema`, `dependencies`.
   - `install.sql`: Kịch bản DDL/DML cài đặt schema, bảng, chỉ mục, hàm và chính sách RLS.
   - `uninstall.sql`: Kịch bản dọn dẹp sạch sẽ schema và thu hồi đăng ký trong `system_plugins`.
   - `README.md`: Tài liệu hướng dẫn chuyên biệt cho từng domain.
3. **Cờ `is_system` (Bảo vệ bất biến)**:
   - Plugin nào có `is_system = true` (như `core-iam`) là hạt nhân nền tảng, cơ chế database cấm tuyệt đối thao tác gỡ bỏ.
4. **Thứ Tự Cài Đặt Topo (Topological Installation Order)**:
   - Thứ tự chuẩn: `storage` (Hạ tầng lưu trữ) $\rightarrow$ `subscriptions` (Hạn ngạch thanh toán) $\rightarrow$ `webhooks` (Hạ tầng sự kiện) $\rightarrow$ `automa` (Nghiệp vụ tự động hóa). Được tự động hóa qua kịch bản `scripts/plugins/apply_plugins.ps1`.

---

### 3.3. Phân Vùng Lưu Trữ & Media Assets (Storage Domain)

1. **`Storage` (Không Dùng Từ `Vault`)**:
   - **Định nghĩa**: Dịch vụ lưu trữ và phân phối tệp đa phương tiện đám mây dựa trên Supabase Storage Engine.
   - **Quy tắc cấm**: Tuyệt đối KHÔNG dùng từ `Vault` để chỉ tính năng lưu trữ tệp của Cloud. Từ `Vault` chỉ tồn tại trong `tuquet-automa` để chỉ thư mục kịch bản offline trên ổ cứng cục bộ (`apps/vault`).
2. **`Media Asset` (Bảng `media.assets`)**:
   - **Định nghĩa**: Bản ghi siêu dữ liệu (metadata) của tệp tin tải lên: đường dẫn tệp (`file_path`), định dạng (`mime_type`), dung lượng (`file_size_bytes`), kích thước ảnh (`metadata JSONB`).
   - **Schema**: Nằm trong schema `media` (Tránh xung đột với schema nội bộ `storage` của Supabase).
3. **`Dual-Layer Storage RLS` (Bảo Mật 2 Lớp)**:
   - Lớp 1: RLS trên bảng hệ thống `storage.objects` bảo vệ tệp vật lý theo tiền tố đường dẫn `(storage.foldername(name))[1]::uuid = active_tenant_id`.
   - Lớp 2: RLS trên bảng `media.assets` bảo vệ quyền truy vấn và chỉnh sửa siêu dữ liệu của tệp.

---

### 3.4. Phân Vùng Thuê Bao & Quản Lý Định Mức (Subscriptions & Quota Metering)

1. **`Plan` (Bảng `billing.plans`)**:
   - **Định nghĩa**: Bậc gói cước dịch vụ SaaS được mở bán (`free`, `pro`, `enterprise`).
   - **Các trường hạn ngạch cốt lõi**: `max_members`, `max_storage_mb`, `max_monthly_runs`.
2. **`Subscription` (Bảng `billing.subscriptions`)**:
   - **Định nghĩa**: Trạng thái đăng ký gói cước thực tế của một Tenant (`tenant_id UNIQUE`).
   - **Trạng thái**: Enum chuẩn hóa (`free_tier`, `trialing`, `active`, `past_due`, `canceled`, `unpaid`).
3. **`Usage Meter` (Bảng `billing.usage_meters`)**:
   - **Định nghĩa**: Đồng hồ đo lường lượng tài nguyên đã sử dụng trong chu kỳ thanh toán hiện tại.
   - **Cặp khóa duy nhất**: `(tenant_id, metric_name)` với các chỉ số đo lường: `storage_mb`, `monthly_runs`.
4. **Hàm Kiểm Tra Định Mức Nguyên Tử (Atomic Quota Checks)**:
   - `billing.check_quota_available(_tenant_id, _metric, _increment)`: Trả về BOOLEAN xem Tenant còn đủ hạn ngạch để thực hiện tác vụ không.
   - `billing.record_usage(_tenant_id, _metric, _amount)`: Ghi nhận mức tiêu thụ mới vào đồng hồ đo lường.

---

### 3.5. Phân Vùng Hàng Đợi Sự Kiện & Webhooks (Transactional Outbox)

1. **`Transactional Outbox` (Bảng `events.outbox`)**:
   - **Định nghĩa**: Mẫu thiết kế phân tán ghi nhận sự kiện phát sinh trong cùng một database transaction với dữ liệu nghiệp vụ, đảm bảo tính nguyên tử tuyệt đối (ACID).
   - **Quy tắc cấm**: Tuyệt đối KHÔNG giả định hoặc viết docs về các Message Broker bên thứ ba (như Kafka, RabbitMQ, Redis BullMQ). Hệ thống sử dụng thuần túy bảng PostgreSQL `events.outbox` với Partial Index `WHERE status = 'pending'`.
2. **`Webhook Subscription` (Bảng `events.subscriptions`)**:
   - **Định nghĩa**: Cấu hình đăng ký nhận webhook của đối tác bên ngoài (`target_url`, `secret_hash`, `is_active`).
3. **`Webhook Delivery` (Bảng `events.deliveries`)**:
   - **Định nghĩa**: Nhật ký lịch sử mỗi lần worker bắn HTTP POST tới endpoint đích (mã phản hồi HTTP `response_status`, nội dung phản hồi `response_body`, thời gian thực hiện).

---

### 3.6. Phân Vùng Tự Động Hóa Phân Tán (Automa Cloud Bridge)

1. **`Workflow` (Bảng `automa.workflows`)**:
   - **Định nghĩa**: Kịch bản tự động hóa trực quan dạng đồ thị nốt (Node Graph AST), tương thích cấu trúc JSON của VueFlow trên Chrome Extension và Desktop Studio.
2. **`Runner` (Bảng `automa.runners`)**:
   - **Định nghĩa**: Máy trạm thực thi kịch bản (Desktop Workstation chạy Windows/macOS hoặc Cloud VPS Linux chạy daemon Rust `apps/core`).
   - **Quy tắc cấm**: Tuyệt đối KHÔNG gọi là "Agent Node", "Bot" hay "Worker". Từ chuẩn là **`Runner`**.
3. **`Browser` (Quy Tắc Bất Biến Về Trình Duyệt Chống Phát Hiện)**:
   - **Định nghĩa**: Thực thể trình duyệt ảo độc lập (`*.browser.json`) chứa fingerprint, proxy, cookie và storage riêng biệt.
   - **Quy tắc cấm**: Tuyệt đối **CẤM** dùng từ `Profile` hoặc `Member` để chỉ phiên bản trình duyệt trong ngữ cảnh Automa (tránh xung đột với `public.profiles` của người dùng).
4. **`Campaign Run` (Bảng `automa.campaign_runs`)**:
   - **Định nghĩa**: Phiên thực thi chiến dịch tự động hóa trên một hoặc nhiều Runners.
5. **`Execution Log` (Bảng `automa.execution_logs`)**:
   - **Định nghĩa**: Dòng nhật ký telemetry phát sinh theo thời gian thực của từng khối lệnh trong một phiên chạy kịch bản.

---

## 4. Bảng Quy Chuẩn Đặt Tên Kỹ Thuật (Naming Conventions)

| Đối Tượng | Quy Chuẩn Đặt Tên | Ví Dụ Đúng Chuẩn | Ví Dụ Sai Phạm |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema** | `snake_case`, danh từ số ít | `public`, `media`, `billing`, `events`, `automa` | `MediaSchema`, `medias`, `billing_v1` |
| **PostgreSQL Table** | `snake_case`, danh từ số nhiều | `tenants`, `profiles`, `roles`, `assets`, `campaign_runs` | `tenant`, `tbl_profiles`, `TenantMember` |
| **PostgreSQL Column** | `snake_case` | `tenant_id`, `created_at`, `is_installed`, `file_size_bytes` | `tenantId`, `createdDate`, `IsSystem` |
| **Primary Key** | Luôn là `id` | `id UUID PRIMARY KEY`, `id BIGINT GENERATED ALWAYS AS IDENTITY` | `tenant_id PK`, `profile_id PK`, `uuid` |
| **Foreign Key** | `<table>_id` | `tenant_id REFERENCES public.tenants(id)` | `id_tenant`, `tenant_ref`, `fk_tenant` |
| **Function Name** | `snake_case`, động từ đứng đầu | `get_user_tenant_ids()`, `has_permission()`, `record_usage()` | `UserTenants()`, `checkPermission()`, `fn_usage` |
| **Permission Code** | `<module>:<resource>:<action>` | `automa:campaigns:run`, `media:assets:delete`, `tenants:read` | `RUN_CAMPAIGN`, `can_delete_media`, `admin` |
| **Plugin Folder** | `kebab-case` hoặc `lowercase` | `core-iam`, `storage`, `subscriptions`, `webhooks`, `automa` | `PluginStorage`, `01_storage`, `sub_scripts` |

---

## 5. Bảng Kiểm Tra Chống Ảo Giác Trước Khi Viết Docs / Code (Pre-Flight Checklist)

Trước khi commit bất kỳ dòng tài liệu hoặc code nào liên quan đến `tuquet-cloud`, tác giả (kỹ sư hoặc AI agent) **bắt buộc kiểm tra danh sách 10 điểm** sau:

- [ ] **1. Kiểm tra Tenant**: Tôi có vô tình dùng từ `Workspace`, `Organization`, `Team` hay `Project` làm tên bảng hoặc tên trường thay vì `Tenant` / `tenant_id` không?
- [ ] **2. Kiểm tra User vs Profile**: Tôi có trỏ khóa ngoại liên kết người dùng vào `public.profiles(id)` thay vì gọi trực tiếp `auth.users` không?
- [ ] **3. Kiểm tra Role vs Permission**: Quyền hạn của tôi có tuân thủ cấu trúc 3 cấp `<module>:<resource>:<action>` và được gán qua `role_permissions` thay vì gán trực tiếp cho người dùng không?
- [ ] **4. Kiểm tra Plugin ID**: Plugin của tôi có nằm trong danh sách 5 phân hệ chuẩn (`core-iam`, `storage`, `subscriptions`, `webhooks`, `automa`) với Postgres schema riêng không?
- [ ] **5. Kiểm tra Cấm Vault**: Trong ngữ cảnh lưu trữ đám mây, tôi có dùng đúng từ `Storage` / `media.assets` và loại bỏ 100% từ `Vault` không?
- [ ] **6. Kiểm tra Cấm Browser Profile**: Khi đề cập đến trình duyệt tự động hóa, tôi có gọi là `Browser` thay vì `Profile` để tránh nhầm với người dùng không?
- [ ] **7. Kiểm tra Runner**: Nút máy trạm thực thi có được gọi đúng là `Runner` (`automa.runners`) thay vì `Worker` hay `Bot` không?
- [ ] **8. Kiểm tra Outbox**: Hàng đợi sự kiện có được gọi đúng là `Transactional Outbox` (`events.outbox`) thay vì bịa ra Message Broker bên ngoài không?
- [ ] **9. Kiểm tra Bảo Vệ CWE-426**: Mọi function và trigger SQL mới có khai báo `SET search_path = ''` và gọi tên bảng tường minh (`public.profiles`) không?
- [ ] **10. Kiểm tra PostgREST API**: Tôi có tránh việc tạo file JSON tĩnh thủ công và dựa vào cơ chế soi chiếu động của PostgREST tại `/rest/v1/` không?
