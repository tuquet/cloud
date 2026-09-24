# 💎 Plugin: Subscriptions & Quota Metering (`subscriptions`)

## 1. Tổng Quan
Plugin quản lý gói cước SaaS đa cấp độ (`subscription_plans`), trạng thái thuê bao của từng Tenant (`tenant_subscriptions`), đo lường mức sử dụng (`usage_meters`), và tự động kích hoạt trigger chặn vượt hạn ngạch dự án (`check_tenant_quota()`).

* **Gói cước mặc định:** Free (3 projects, 2 members), Pro (25 projects, 10 members), Enterprise (500 projects, 100 members).
* **Cài đặt:** `install.sql`.
* **Gỡ bỏ:** `uninstall.sql`.
