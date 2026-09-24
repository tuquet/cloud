# 💼 Plugin: Demo Projects Resource (`demo-projects`)

## 1. Tổng Quan
Plugin cung cấp bảng nghiệp vụ mẫu `public.projects` chứng minh kiến trúc cắm ghép (plugin) vào nền tảng Base Core IAM của `tuquet-cloud`.

* **Phụ thuộc:** `core-iam`.
* **Phạm vi bảo mật:** Phân lập tuyệt đối theo `tenant_id` của bảng `public.tenants`.
* **Quyền hạn bổ sung:**
  - `projects:read`: Xem danh sách và chi tiết dự án.
  - `projects:create`: Tạo dự án mới.
  - `projects:update`: Chỉnh sửa dự án.
  - `projects:delete`: Xóa bỏ dự án.
* **Cài đặt:** Chạy `install.sql`.
* **Gỡ bỏ:** Chạy `uninstall.sql`.
