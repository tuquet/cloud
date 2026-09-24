# 🤖 Module: Automa Cloud Bridge (`automa_*`)

## 1. Tổng Quan Kiến Trúc
Phân vùng **Automa Cloud Bridge** cung cấp hạ tầng dữ liệu đám mây (Cloud BaaS) đa tổ chức (Multi-tenant) phục vụ hệ sinh thái tự động hóa trình duyệt phân tán `tuquet-automa`.

### Trách Nhiệm Cốt Lõi:
1. **Lưu trữ & Đồng bộ quy trình (`automa_workflows`)**: Quản lý AST đồ thị nodes/edges trực quan, biến tham số, và phiên bản quy trình theo từng Tenant.
2. **Quản trị hạm đội máy trạm (`automa_runners`)**: Đăng ký các node máy trạm thực thi chạy Rust daemon (`automa-core`), theo dõi heartbeat thời gian thực, IP, HWID fingerprint và năng lực xử lý (concurrency).
3. **Điều phối & Giám sát chiến dịch (`automa_campaign_runs`)**: Quản lý các phiên chạy tự động hóa theo lô, phân bổ máy trạm thực thi, cập nhật tiến độ % và kết quả.
4. **Nhật ký & Telemetry chi tiết (`automa_execution_logs`)**: Thu thập stream log từng bước chạy, cảnh báo lỗi và phục vụ hiển thị live console.
5. **Kích hoạt tự động theo lịch (`automa_schedules`)**: Quản lý lịch chạy tự động theo biểu thức Cron chuẩn.

---

## 2. Quy Tắc Đặt Tên Bất Biến (Naming Invariant)
* **Tiền tố bắt buộc:** Toàn bộ bảng, kiểu ENUM và trigger thuộc module này **BẮT BUỘC** phải có tiền tố `automa_*` (ví dụ: `automa_workflows`, `automa_runners`, `automa_campaign_runs`).
* **Ranh giới Tenant:** Mọi bảng nghiệp vụ đều chứa cột `tenant_id NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE`.
* **Chỉ mục kết hợp (Composite Index):** Mọi chỉ mục tìm kiếm và lọc đều bắt đầu bằng `tenant_id` để tối ưu hóa quét bảng trong phạm vi tổ chức và ngăn chặn rò rỉ chéo.

---

## 3. Cấu Trúc File & Hướng Dẫn Chạy Migration (UP & DOWN)

```
supabase/modules/automa/
├── 01_automa_up.sql      # Script UP: Khởi tạo Enums, Bảng, Composite Indexes, Triggers, RBAC, RLS
├── 02_automa_down.sql    # Script DOWN: Thu hồi Rollback an toàn 100% không để lại rác (Zero-orphan)
└── README.md             # Tài liệu đặc tả module
```

### Cách 1: Chạy qua Supabase CLI Migration (Toàn Cục)
File đã được liên kết trực tiếp vào luồng migration tuần tự:
- UP: `supabase/migrations/20260924000005_automa_cloud_bridge.sql`
- DOWN: `supabase/migrations/20260924000005_automa_cloud_bridge.down.sql`

```bash
# Áp dụng migration UP
supabase migration up

# Hoặc Rollback migration DOWN gần nhất
supabase migration down --last 1
```

### Cách 2: Chạy trực tiếp qua Supabase SQL Editor / DBeaver
1. Mở file `01_automa_up.sql` $\rightarrow$ Nhấn **Run** để khởi tạo toàn bộ phân vùng `automa_*`.
2. Khi cần hủy bỏ hoặc reset module: Mở file `02_automa_down.sql` $\rightarrow$ Nhấn **Run** để dọn dẹp sạch sẽ các bảng, trigger và quyền `automa:*`.

---

## 4. Danh Mục Quyền Hạn RBAC (Permissions)

| Permission ID | Mô Tả | Gán Cho Roles |
| :--- | :--- | :--- |
| `automa:workflows:read` | Xem danh sách và chi tiết các quy trình | `owner`, `admin`, `member`, `viewer` |
| `automa:workflows:manage` | Tạo, sửa, xuất bản và xóa quy trình | `owner`, `admin` |
| `automa:runners:read` | Xem danh sách máy trạm (runners) và trạng thái | `owner`, `admin`, `member`, `viewer` |
| `automa:runners:manage` | Đăng ký, cấu hình và quản lý các node runners | `owner`, `admin` |
| `automa:campaigns:read` | Xem lịch sử và tiến độ thực thi chiến dịch | `owner`, `admin`, `member`, `viewer` |
| `automa:campaigns:run` | Kích hoạt, tạm dừng hoặc hủy bỏ phiên chạy | `owner`, `admin`, `member` |
| `automa:campaigns:manage` | Cấu hình tham số chiến dịch và lập lịch tự động | `owner`, `admin` |
| `automa:logs:read` | Xem nhật ký chi tiết và telemetry thực thi | `owner`, `admin`, `member`, `viewer` |

---

## 5. Mối Quan Hệ Với `tuquet-automa` (Local Client Runtime)

| Tiêu Chí | `tuquet-automa` (Máy Trạm Cục Bộ) | `tuquet-cloud` (Đám Mây Trung Tâm) |
| :--- | :--- | :--- |
| **Cơ Sở Dữ Liệu** | SQLite 3 (Cục bộ, file `automa.db`) | PostgreSQL / Supabase (Cloud BaaS) |
| **Phạm Vi** | 1 người dùng / 1 máy trạm đơn lẻ | Đa tổ chức (Multi-Tenant RBAC) |
| **Dữ Liệu Nhạy Cảm** | Két sắt mật mã AES-256-CBC lưu RAM-only | Không lưu credentials/passwords thô |
| **Điều Phối** | Axum Engine thực thi trực tiếp qua CDP | PostgREST / Supabase Realtime điều phối |
| **Migration** | `apps/core/migrations/*.sql` (SQLite DDL) | `supabase/modules/automa/*.sql` (Postgres DDL) |
