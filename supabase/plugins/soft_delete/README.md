# 🗑️ Plugin: Soft Delete & Data Retention (`soft_delete`)

## 1. Tổng Quan
Plugin bổ sung cột `deleted_at` cho bảng nghiệp vụ (`projects`), cung cấp tính năng Thùng rác (Recycle Bin), tự động lọc bản ghi bị xóa khỏi view người dùng thường và các hàm khôi phục/xóa vĩnh viễn (`soft_delete_project`, `restore_project`, `hard_delete_project`).

* **Cài đặt:** `install.sql`.
* **Gỡ bỏ:** `uninstall.sql`.
