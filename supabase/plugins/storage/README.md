# 📁 Enterprise Plugin: Media Storage Assets (`storage`)

> **Quản Lý Metadata Tệp & Phân Lập Storage Bucket Đa Tổ Chức**  
> Cung cấp cơ mục lục lưu trữ metadata tệp đa phương tiện (`media.assets`), tự động khởi tạo Supabase Storage Bucket `tenant-assets` và thiết lập ma trận chính sách Row Level Security (RLS) bảo vệ tệp theo ranh giới `tenant_id`.

---

## 1. Thông Số Kiến Trúc (Architecture Specs)

| Thuộc Tính | Chi Tiết Kỹ Thuật |
|---|---|
| **Plugin ID** | `storage` |
| **Phân Loại** | **On-Demand Infrastructure Plugin** |
| **PostgreSQL Schema** | `media` (Tránh xung đột với schema gốc `storage` của Supabase) |
| **Storage Bucket** | `tenant-assets` (Private, Giới hạn: 50MB/tệp) |
| **Quy Tắc Đường Dẫn Tệp** | `tenant-assets/{tenant_id}/{timestamp}_{filename}` |
| **Phiên Bản** | `1.0.0` |
| **Phụ Thuộc (Dependencies)** | `core-iam` |
| **Kịch Bản Cài Đặt** | [`install.sql`](install.sql) |
| **Kịch Bản Gỡ Bỏ** | [`uninstall.sql`](uninstall.sql) |

---

## 2. Bảng Dữ Liệu: `media.assets`

Bảng `media.assets` lưu trữ thông tin nghiệp vụ và siêu dữ liệu kỹ thuật của mọi tập tin được tải lên:

| Cột | Kiểu Dữ Liệu | Ràng Buộc & Ý Nghĩa |
|---|---|---|
| `id` | `UUID` | Khóa chính (`gen_random_uuid()`) |
| `tenant_id` | `UUID NOT NULL` | FK $\rightarrow$ `public.tenants(id)` ON DELETE CASCADE |
| `file_path` | `TEXT NOT NULL` | Đường dẫn tương đối trong bucket (vd: `b000.../banner.png`) |
| `bucket_name` | `TEXT NOT NULL` | Mặc định `'tenant-assets'` |
| `original_name` | `TEXT NOT NULL` | Tên gốc của tệp khi tải lên |
| `mime_type` | `TEXT NOT NULL` | vd: `image/webp`, `video/mp4`, `application/pdf` |
| `file_size_bytes` | `BIGINT NOT NULL` | Dung lượng tệp tính bằng bytes (`CHECK >= 0`) |
| `metadata` | `JSONB NOT NULL` | Chiều cao, chiều rộng, EXIF, mã hash SHA-256,... |
| `created_by` | `UUID` | FK $\rightarrow$ `public.profiles(id)` ON DELETE SET NULL |
| `created_at` | `TIMESTAMPTZ` | Thời điểm tải lên |
| `updated_at` | `TIMESTAMPTZ` | Thời điểm cập nhật metadata |

---

## 3. Kiến Trúc Bảo Mật Storage RLS 2 Lớp (Dual-Layer RLS)

Hệ thống bảo vệ tài nguyên tệp thông qua 2 lớp phòng vệ độc lập:

```
[Client Request]
       │
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 1. Tầng Storage Object RLS (storage.objects)                │
 │    Kiểm tra path: (storage.foldername(name))[1]::uuid       │
 │    Chỉ cho phép đọc/ghi nếu thuộc tenant_id của User        │
 └─────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 2. Tầng Metadata Catalog RLS (media.assets)                 │
 │    Kiểm tra quyền hạn chi tiết:                             │
 │    - media:read                                             │
 │    - media:upload                                           │
 │    - media:delete                                           │
 └─────────────────────────────────────────────────────────────┘
```

### Chính Sách RLS Trên `storage.objects`:
* **SELECT**: `bucket_id = 'tenant-assets' AND (storage.foldername(name))[1]::uuid IN (SELECT public.get_user_tenant_ids())`
* **INSERT**: `bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:upload')`
* **DELETE**: `bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:delete')`

---

## 4. Từ Điển Quyền Hạn (Permissions)

| Permission ID | Module | Mô Tả Nghiệp Vụ | Owner | Admin | Member |
|---|---|---|:---:|:---:|:---:|
| `media:read` | `media` | Xem và tải về tài nguyên media của tổ chức | ✅ | ✅ | ✅ |
| `media:upload` | `media` | Tải tập tin mới lên bucket của tổ chức | ✅ | ✅ | ❌ |
| `media:delete` | `media` | Xóa tập tin khỏi kho lưu trữ | ✅ | ✅ | ❌ |

---

## 5. Ví Dụ Sử Dụng Qua Supabase SDK

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient('https://<project-ref>.supabase.co', '<anon-key>');

async function uploadTenantAsset(tenantId: string, file: File) {
  const filePath = `${tenantId}/${Date.now()}_${file.name}`;

  // Bước 1: Upload nhị phân lên Supabase Storage Bucket
  const { data: storageData, error: storageErr } = await supabase.storage
    .from('tenant-assets')
    .upload(filePath, file);

  if (storageErr) throw storageErr;

  // Bước 2: Lưu metadata vào catalog media.assets
  const { data: asset, error: assetErr } = await supabase
    .schema('media')
    .from('assets')
    .insert({
      tenant_id: tenantId,
      file_path: filePath,
      bucket_name: 'tenant-assets',
      original_name: file.name,
      mime_type: file.type,
      file_size_bytes: file.size,
      metadata: { uploaded_via: 'web_studio' }
    })
    .select()
    .single();

  return asset;
}
```

---

## 6. Quy Trình Vòng Đời (Lifecycle)

### Cài Đặt (Installation)
```powershell
supabase db query --local -f supabase/plugins/storage/install.sql
```

### Gỡ Bỏ (Uninstallation)
```powershell
supabase db query --local -f supabase/plugins/storage/uninstall.sql
```
Xóa bỏ chính sách RLS trên `storage.objects`, thực thi `DROP SCHEMA IF EXISTS media CASCADE;`, và xóa các quyền hạn `media:*` khỏi Core IAM một cách an toàn tuyệt đối.
