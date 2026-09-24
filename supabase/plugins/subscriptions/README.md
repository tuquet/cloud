# 💎 Plugin: Subscriptions & Quota Metering (`subscriptions`)

## 1. Tổng Quan
Plugin quản lý gói cước SaaS đa cấp độ (`billing.plans`), trạng thái thuê bao của từng Tenant (`billing.subscriptions`), đo lường mức sử dụng tài nguyên động (`billing.usage_meters`), và cung cấp hàm kiểm tra và ghi nhận định mức sử dụng (`billing.check_tenant_quota()`, `billing.record_usage()`).

* **Kiến trúc:** Schema chuyên biệt `billing`.
* **Gói cước mặc định:**
  - **Free:** 2 members, 500MB storage, 1,000 monthly automation runs ($0/tháng).
  - **Pro:** 10 members, 10GB storage, 50,000 monthly automation runs ($29/tháng).
  - **Enterprise:** 100 members, 100GB storage, 1,000,000 monthly automation runs ($199/tháng).
* **Cài đặt:** `install.sql`.
* **Gỡ bỏ:** `uninstall.sql`.
