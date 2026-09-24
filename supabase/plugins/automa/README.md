# 🔌 Plugin: Automa Cloud Bridge (`automa_*`)

## 1. Tổng Quan Kiến Trúc Plugin
**`automa`** là một **Optional Extension Plugin** được thiết kế độc lập với Base Core của `tuquet-cloud`.
* **Base Core (`tuquet-cloud`):** Đảm nhiệm IAM, Quản lý Tenant, Multi-Tenant RBAC, Storage Assets, Subscriptions & Quota, và Transactional Outbox.
* **Automa Plugin:** Cung cấp hạ tầng phân tán để kết nối với cỗ máy tự động hóa trình duyệt `tuquet-automa` (`apps/core` Rust Daemon).

> [!IMPORTANT]
> Plugin này **không nằm trong Base Core Migrations** (`supabase/migrations/`). Nó có thể được cài đặt (install) hoặc gỡ bỏ (uninstall) linh hoạt bất kỳ lúc nào mà không ảnh hưởng tới dữ liệu khách hàng và người dùng của Base Core.

---

## 2. Cấu Trúc File

```
supabase/plugins/automa/
├── install.sql       # Script cài đặt: Enums, bảng automa_*, triggers, composite indexes, RLS, permissions
├── uninstall.sql     # Script gỡ bỏ: DROP toàn bộ bảng automa_*, triggers, và dọn sạch quyền (Zero-orphan)
├── seed.sql          # Dữ liệu mẫu (Workflows, Runners, Campaigns, Logs, Schedules)
└── README.md         # Hướng dẫn kiến trúc & sử dụng
```

---

## 3. Cách Cài Đặt (Install) & Gỡ Bỏ (Uninstall)

### Cách 1: Chạy trực tiếp qua Supabase SQL Editor / DBeaver
* **Khi cần kích hoạt tính năng Automa:**  
  Mở file `install.sql` $\rightarrow$ Nhấn **Run** (F5). (Tùy chọn: Chạy thêm `seed.sql` để nạp dữ liệu mẫu).
* **Khi không cần hoặc muốn gỡ bỏ hoàn toàn:**  
  Mở file `uninstall.sql` $\rightarrow$ Nhấn **Run** (F5). Hệ thống sẽ dọn dẹp 100% sạch sẽ toàn bộ bảng `automa_*` và thu hồi quyền `automa:*`.

### Cách 2: Chạy qua Supabase CLI / Bash
```bash
# Cài đặt Plugin
supabase db execute -f supabase/plugins/automa/install.sql

# Nạp dữ liệu mẫu cho Plugin (Optional)
supabase db execute -f supabase/plugins/automa/seed.sql

# Gỡ bỏ Plugin
supabase db execute -f supabase/plugins/automa/uninstall.sql
```

---

## 4. Danh Mục Quyền Hạn RBAC Thuộc Plugin

| Permission ID | Mô Tả | Gán Cho Roles |
| :--- | :--- | :--- |
| `automa:workflows:read` | Xem danh sách và đồ thị workflow | `owner`, `admin`, `member` |
| `automa:workflows:manage` | Tạo, sửa, xuất bản và xóa workflow | `owner`, `admin` |
| `automa:runners:read` | Xem danh sách và trạng thái runner nodes | `owner`, `admin`, `member` |
| `automa:runners:manage` | Đăng ký và cấu hình máy trạm runner | `owner`, `admin` |
| `automa:campaigns:read` | Xem lịch sử và tiến độ phiên chạy | `owner`, `admin`, `member` |
| `automa:campaigns:run` | Kích hoạt phiên chạy quy trình | `owner`, `admin`, `member` |
| `automa:campaigns:manage` | Cấu hình tham số và lập lịch Cron | `owner`, `admin` |
| `automa:logs:read` | Xem nhật ký telemetry và log chi tiết | `owner`, `admin`, `member` |
