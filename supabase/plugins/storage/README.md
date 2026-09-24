# 📁 Enterprise Plugin: Media Storage Assets (`storage`)

> **Multi-Tenant File Metadata Catalog & Isolated Storage Bucket Security**  
> Provides an isolated metadata catalog for multi-tenant media assets (`media.assets`), automatically provisions the private Supabase Storage Bucket `tenant-assets`, and enforces dual-layer Row-Level Security (RLS) policies scoped strictly by `tenant_id`.  
> 📖 **Terminology Standard**: Review the [**Terminology Dictionary & Anti-Hallucination Lexicon (docs/terminology_dictionary.md)**](../../../docs/terminology_dictionary.md) for strict naming invariants and forbidden terms (the term "Vault" is forbidden for cloud storage).

---

## 1. Architectural Specifications

| Property | Technical Specification |
|---|---|
| **Plugin ID** | `storage` |
| **Classification** | **On-Demand Infrastructure Plugin** |
| **PostgreSQL Schema** | `media` (Avoids collision with Supabase's internal `storage` schema) |
| **Storage Bucket** | `tenant-assets` (Private, 50MB per file upload limit) |
| **Storage Path Convention** | `tenant-assets/{tenant_id}/{timestamp}_{filename}` |
| **Version** | `1.0.0` |
| **Dependencies** | `core-iam` |
| **Installation Script** | [`install.sql`](install.sql) |
| **Uninstallation Script** | [`uninstall.sql`](uninstall.sql) |

---

## 2. Table Directory: `media.assets`

The `media.assets` catalog records technical and operational metadata for all uploaded assets:

| Column | Data Type | Constraints & Description |
|---|---|---|
| `id` | `UUID` | Primary Key (`gen_random_uuid()`) |
| `tenant_id` | `UUID NOT NULL` | FK $\rightarrow$ `public.tenants(id)` ON DELETE CASCADE |
| `file_path` | `TEXT NOT NULL` | Relative object path inside the bucket (e.g. `b000.../banner.png`) |
| `bucket_name` | `TEXT NOT NULL` | Defaults to `'tenant-assets'` |
| `original_name` | `TEXT NOT NULL` | Original client file name |
| `mime_type` | `TEXT NOT NULL` | e.g., `image/webp`, `video/mp4`, `application/pdf` |
| `file_size_bytes` | `BIGINT NOT NULL` | File size in bytes (`CHECK >= 0`) |
| `metadata` | `JSONB NOT NULL` | Dimensions, EXIF, SHA-256 hash, upload context |
| `created_by` | `UUID` | FK $\rightarrow$ `public.profiles(id)` ON DELETE SET NULL |
| `created_at` | `TIMESTAMPTZ` | Upload timestamp |
| `updated_at` | `TIMESTAMPTZ` | Last metadata modification timestamp |

---

## 3. Dual-Layer Storage Security Architecture

Media assets are protected across two independent security layers:

```
[Client Request]
       │
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 1. Storage Object RLS (storage.objects)                     │
 │    Path inspection: (storage.foldername(name))[1]::uuid     │
 │    Enforces physical file access only to member's tenant    │
 └─────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 2. Metadata Catalog RLS (media.assets)                      │
 │    Evaluates granular atomic permissions:                   │
 │    - media:read                                             │
 │    - media:upload                                           │
 │    - media:delete                                           │
 └─────────────────────────────────────────────────────────────┘
```

### RLS Policies on `storage.objects`:
* **SELECT**: `bucket_id = 'tenant-assets' AND (storage.foldername(name))[1]::uuid IN (SELECT public.get_user_tenant_ids())`
* **INSERT**: `bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:upload')`
* **DELETE**: `bucket_id = 'tenant-assets' AND public.has_tenant_permission((storage.foldername(name))[1]::uuid, 'media:delete')`

---

## 4. Permissions Dictionary

| Permission ID | Module | Business Capability | Owner | Admin | Member |
|---|---|---|:---:|:---:|:---:|
| `media:read` | `media` | View and download tenant media assets | ✅ | ✅ | ✅ |
| `media:upload` | `media` | Upload new media files to tenant storage | ✅ | ✅ | ❌ |
| `media:delete` | `media` | Delete media assets from storage | ✅ | ✅ | ❌ |

---

## 5. Client Consumption Example (Supabase JS SDK)

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient('https://<project-ref>.supabase.co', '<anon-key>');

async function uploadTenantAsset(tenantId: string, file: File) {
  const filePath = `${tenantId}/${Date.now()}_${file.name}`;

  // Step 1: Upload binary payload to Supabase Storage Bucket
  const { data: storageData, error: storageErr } = await supabase.storage
    .from('tenant-assets')
    .upload(filePath, file);

  if (storageErr) throw storageErr;

  // Step 2: Store metadata in the media.assets catalog table
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

  if (assetErr) throw assetErr;
  return asset;
}
```

---

## 6. Lifecycle Management

### Installation
```powershell
supabase db query --local -f supabase/plugins/storage/install.sql
```

### Uninstallation
```powershell
supabase db query --local -f supabase/plugins/storage/uninstall.sql
```
Drops RLS policies on `storage.objects`, executes `DROP SCHEMA IF EXISTS media CASCADE;`, and purges `media:*` permissions from the Core IAM registry.
