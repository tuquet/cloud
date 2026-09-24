# 🤖 Plugin: Automa Cloud Bridge (`automa`)

## 1. Tổng Quan Kiến Trúc
* **Dedicated Schema:** `automa` (tách biệt hoàn toàn khỏi `public`).
* **PostgREST Enpoints:** `/rest/v1/automa/workflows`, `/rest/v1/automa/runners`, v.v.
* **Cài đặt:** `install.sql` (Tạo schema `automa` & đăng ký vào `public.system_plugins`).
* **Gỡ bỏ:** `uninstall.sql` (Thực thi `DROP SCHEMA automa CASCADE;` nguyên tử không để lại rác).
