# 📁 Plugin: Media Storage Assets (`storage`)

## 1. Tổng Quan
Plugin quản lý metadata tài nguyên media (`public.media_assets`) và cấu hình chính sách bảo mật RLS phân lập đa tổ chức cho Supabase Storage Bucket `tenant-assets`.

* **Định tuyến thư mục:** `tenant-assets/{tenant_id}/{file_name}`.
* **Quyền hạn:** `media:read`, `media:upload`, `media:delete`.
* **Cài đặt:** `install.sql`.
* **Gỡ bỏ:** `uninstall.sql`.
