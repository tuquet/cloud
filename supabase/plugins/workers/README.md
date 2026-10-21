# ⚡ Cloud Plugin: Workers, Cloud Browsers & Compute Fleet

**Plugin ID:** `workers`  
**Schema:** `workers`  
**Version:** `1.0.0`  
**Dependencies:** `["core-iam"]`

---

## 📖 Overview
The `workers` plugin acts as the universal compute infrastructure foundation and virtual browser profile manager for Cloud. It manages physical workstations, edge nodes, cloud worker daemons running `tq worker` (Worker in Rust), proxy pools, deterministic C++ hardware fingerprints, and distributed session storage synchronization.

---

## 🏛️ Schema Architecture

### 1. Tables (`schema: workers`)
- **`workers.devices`**: Multi-tenant registry of enrolled physical workstations and cloud worker nodes with CPU/RAM metrics and hardware fingerprint.
- **`workers.browsers`**: Central cloud inventory of virtual anti-detect browser profiles (GoLogin/AdsPower standard) with deterministic hardware fingerprints (seed, OS, WebRTC, CPU/RAM, languages, proxies) and session storage pointers (`.zip`).
- **`workers.proxies`**: Multi-tenant pool of residential, datacenter, mobile, and SOCKS5 proxies with live latency tracking and health checking.
- **`workers.node_browsers`**: Registry of node-local browser profiles discovered on edge worker PCs.

### 2. Storage Bucket
- **`browser-profiles`**: Private Supabase Storage bucket (256MB limit per archive) storing compressed session snapshot archives (`<tenant_id>/<browser_id>.zip`).

### 3. Core RPC Procedures & PostgREST Facades
- **`workers.enroll_device(...)`**: Idempotent RPC endpoint for zero-touch device onboarding with secure token hashing.
- **`workers.heartbeat(...)`**: Telemetry and liveness RPC endpoint (also exposed as `public.heartbeat`).
- **`workers.acquire_browser(...)`**: Distributed lease acquisition with Optimistic Overwrite (Last-Write-Wins) and real-time In-Use Advisory Warning (also exposed as `public.acquire_browser`).
- **`workers.release_browser(...)`**: Session storage snapshot sync and transition back to `idle` (also exposed as `public.release_browser`).
- **`workers.create_browser(...)`**: Deterministic browser profile generation with PRNG seed and tenant verification (also exposed as `public.create_browser`).
- **`workers.list_browsers(...)`**: Secure tenant-scoped profile listing with device token authentication (also exposed as `public.list_browsers`).
- **`workers.reap_stale_browser_locks(...)`**: Data Engine Dead Lease Reaper that automatically frees browser locks when a workstation has stopped heartbeating (also exposed as `public.reap_stale_browser_locks`).
- **`workers.claim_proxy(...)`**: Atomically checks out an active proxy from the pool.
- **`workers.sync_proxies(...)`**: Batch syncs proxies from workstation into the tenant pool.

---

## 🔑 Permissions

| Permission ID | Module | Business Capability | Owner | Admin | Member |
|---|---|---|:---:|:---:|:---:|
| `workers:devices:read` | `workers` | View registered compute nodes and live telemetry | ✅ | ✅ | ✅ |
| `workers:devices:manage` | `workers` | Configure, pause, or remove worker devices | ✅ | ✅ | ❌ |
| `workers:devices:enroll` | `workers` | Enroll new physical workstations and edge nodes | ✅ | ✅ | ❌ |
| `workers:proxies:read` | `workers` | View proxy pool and health status within tenant | ✅ | ✅ | ✅ |
| `workers:proxies:manage` | `workers` | Create, edit, delete, and test proxies | ✅ | ✅ | ❌ |
| `workers:browsers:read` | `workers` | View virtual browser profiles and fingerprint configs | ✅ | ✅ | ✅ |
| `workers:browsers:manage` | `workers` | Create, update, launch, and control browser profiles | ✅ | ✅ | ✅ |

---

## 🚀 Lifecycle Management

### Installation
```powershell
# Via Plugin Pipeline Runner
.\scripts\plugins\apply_plugins.ps1 -Plugin workers -Action install -WithSeed
```

### Uninstallation
```powershell
# Clean uninstallation with zero dangling artifacts
.\scripts\plugins\apply_plugins.ps1 -Plugin workers -Action uninstall
```
