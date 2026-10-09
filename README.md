<div align="center">
  <img src="https://tuquet.com/icons/cloud.svg" width="76" height="76" alt="Cloud Logo" />
  <h1>Specter Cloud (`specter cloud`)</h1>
  <p><strong>Multi-Tenant Foundation & Central Control Plane for Supabase & PostgreSQL 15+</strong></p>

  <p>
    <a href="https://specter.tuquet.com/cloud/"><img src="https://img.shields.io/badge/Docs-VitePress%20Hub-blue.svg" alt="Documentation Hub" /></a>
    <a href="https://github.com/tuquet/scoop-bucket"><img src="https://img.shields.io/badge/Scoop-specter-brightgreen.svg" alt="Scoop" /></a>
    <a href="https://supabase.com"><img src="https://img.shields.io/badge/Supabase-PostgreSQL%2015+-brightgreen.svg" alt="Supabase" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" /></a>
  </p>

  <p>
    <strong><a href="https://specter.tuquet.com/cloud/">📖 Đọc toàn bộ tài liệu kỹ thuật tại Documentation Hub &rarr;</a></strong>
  </p>
</div>

---

## 📌 Tổng Quan (Overview)

**Specter Cloud** là tầng điều khiển trung tâm (Control Plane) cho hạm đội tự động hóa phân tán. Được xây dựng trên nền tảng Supabase và PostgreSQL 15+, Cloud cung cấp kiến trúc đa người dùng (Multi-tenant Micro-kernel), cơ chế phân quyền RBAC dựa trên Claims trong JWT token và hệ thống ghi nhận sự kiện Transactional Outbox bất đồng bộ.

* **Ủy quyền phân tán & RLS Lease**: Đảm bảo thiết bị tại biên (edge worker) tự động đăng ký và nhận lệnh bảo mật qua token không cần round-trip phức tạp.
* **Kiến trúc Plugin Module**: Tách biệt lõi hệ thống bất biến với các plugin nghiệp vụ (runners, automa, storage, webhooks).

## ⚡ Sử Dụng Nhanh (Quickstart)

```bash
# Kiểm tra định danh và trạng thái thiết bị trên Cloud Fleet
specter cloud whoami

# Đăng ký thiết bị hiện tại vào hạm đội Runner
specter cloud enroll
```

## 📚 Tài Liệu Kỹ Thuật Tập Trung (SSOT)

Toàn bộ đặc tả kiến trúc Micro-kernel, mô hình RLS Lease, cấu trúc schema cơ sở dữ liệu và quy trình migration được bảo trì duy nhất tại Documentation Hub:

👉 **[https://specter.tuquet.com/cloud/](https://specter.tuquet.com/cloud/)**
