# ⚡ Plugin: Asynchronous Outbox & Webhooks Queue (`webhooks`)

## 1. Tổng Quan
Plugin cung cấp mô hình Transactional Outbox Pattern (`public.outbox_events`), quản lý danh sách đăng ký Webhook ra ngoài (`public.webhook_subscriptions`), và ghi nhật ký phát sóng HTTP (`public.webhook_deliveries`).

* **Trigger tự động:** Bắt sự kiện tạo/xóa tài nguyên (như `projects`) và lưu vào Outbox.
* **Cài đặt:** `install.sql`.
* **Gỡ bỏ:** `uninstall.sql`.
