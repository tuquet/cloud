# Phân Tích & Hướng Dẫn Xuất OpenAPI Specification Trong Supabase

Tài liệu này đánh giá chi tiết dung lượng tài nguyên hệ thống (RAM), cơ chế tự động sinh **OpenAPI Specification (Swagger)** từ Supabase PostgREST Engine, và hướng dẫn tự động xuất SDK client cho ứng dụng.

---

## 1. Đánh Giá Tài Nguyên Hệ Thống (System Memory & Hardware Check)

| Tiêu Chí | Giá Trị Thực Tế | Đánh Giá Khả Năng Thực Nghiệm Supabase Local |
| :--- | :--- | :--- |
| **Tổng dung lượng RAM (Total RAM)** | **16.0 GB** | Rất mạnh mẽ, thoải mái đáp ứng môi trường phát triển đa ứng dụng. |
| **Dung lượng RAM trống (Free RAM)** | **4.8 GB** | **Sẵn sàng 100%**. Supabase Local (Docker) chỉ chiếm ~1.5 GB - 2.0 GB RAM. |
| **Trạng thái Docker Desktop** | Đã cài đặt tại `C:\Program Files\Docker\Docker\Docker Desktop.exe` | Service `com.docker.service` cần bật 1 lần bằng tay hoặc qua VS Code Task. |

> **Kết luận**: Cấu hình máy cá nhân của bạn hoàn toàn lý tưởng để chạy Supabase Local dài hạn mà không lo thiếu RAM hay giật lag.

---

## 2. Cơ Chế Tự Động Sinh OpenAPI Specification Của Supabase

Supabase tích hợp engine **PostgREST** tự động soi chiếu (Introspect) schema PostgreSQL trong schema `public` và sinh ra chuẩn **OpenAPI v3 Specification** thời gian thực mà không cần viết thủ công 1 dòng code nào:

```
┌──────────────────────────────────────────────┐
│ POSTGRESQL DATABASE SCHEMA (public)          │
│ Bảng: profiles, tenants, roles, permissions...│
└──────────────────────┬───────────────────────┘
                       │ Auto Introspection
                       ▼
┌──────────────────────────────────────────────┐
│ POSTGREST ENGINE / KONG API GATEWAY          │
│ Port 54321 / REST Endpoint                   │
└──────────────────────┬───────────────────────┘
                       │ Exposes OpenAPI Spec
                       ▼
┌──────────────────────────────────────────────┐
│ OPENAPI SPECIFICATION (JSON / YAML)          │
│ URL: http://127.0.0.1:54321/rest/v1/         │
└──────────────────────────────────────────────┘
```

---

## 3. Cách Xuất OpenAPI Spec Từ Supabase Local / Cloud

### Cách 1: Xuất OpenAPI Spec dạng JSON qua HTTP GET
Khi Supabase Local hoặc Cloud đang chạy, bạn chỉ cần gửi 1 request `GET` tới API Gateway:

```powershell
# Cho Supabase Local (Port 54321)
curl.exe -s -H "Accept: application/openapi+json" http://127.0.0.1:54321/rest/v1/ -o docs/openapi_spec_rbac.json

# Cho Supabase Cloud
curl.exe -s -H "apikey: <your-anon-key>" -H "Accept: application/openapi+json" https://<project-ref>.supabase.co/rest/v1/ -o docs/openapi_spec_rbac.json
```

---

### Cách 2: Xem Trực Quan Trên Supabase Studio (Swagger UI)
Mở giao diện Supabase Studio tại:
👉 `http://localhost:54323/project/default/api` (hoặc Dashboard Cloud > **API Docs**).
* Toàn bộ bảng `profiles`, `tenants`, `roles`, `tenant_members`, `projects`... sẽ được liệt kê với đầy đủ ví dụ request, cờ tìm kiếm (filtering), phân trang (pagination), và cờ chọn quyền RLS!

---

## 4. Tự Động Sinh Client SDK Từ OpenAPI Spec (Auto-Generated SDKs)

Một khi đã có file `openapi_spec_rbac.json` (như file chúng tôi đã tạo tại [`docs/openapi_spec_rbac.json`](file:///c:/Users/ndtu6/Repository/tuquet-creator/docs/openapi_spec_rbac.json)), bạn có thể tự động sinh ra Client SDK cho mọi ngôn ngữ lập trình:

### A. Sinh TypeScript Types chuẩn Supabase:
```powershell
# Chạy lệnh có sẵn trong VS Code Task: 'supabase gen types'
supabase gen types typescript --local > types/supabase.ts
```

### B. Sinh REST Client cho Frontend (React, Vue, Flutter, iOS, Android):
```bash
# Dùng openapi-generator-cli sinh code client cho TypeScript / Fetch
npx @openapitools/openapi-generator-cli generate \
  -i docs/openapi_spec_rbac.json \
  -g typescript-fetch \
  -o src/api-client
```

---

## 5. File OpenAPI Specification Mẫu Đã Tạo Nằm Ở Đâu?

Mẫu OpenAPI Specification v3 chuẩn cho toàn bộ 9 bảng Multi-tenant RBAC của hệ thống đã được xuất và lưu sẵn tại:  
📄 **[`docs/openapi_spec_rbac.json`](file:///c:/Users/ndtu6/Repository/tuquet-creator/docs/openapi_spec_rbac.json)**
