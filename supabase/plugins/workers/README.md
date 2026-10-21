# ⚡ Cloud Plugin: Runners, Cloud Browsers & Compute Fleet

**Plugin ID:** `runners`  
**Schema:** `runners`  
**Version:** `1.0.0`  
**Dependencies:** `["core-iam"]`

---

## 📖 Overview
The `runners` plugin acts as the universal compute infrastructure foundation and virtual browser profile manager for Cloud. It manages physical workstations, edge nodes, cloud runner daemons running `runner` (Runner in Rust), proxy pools, deterministic C++ hardware fingerprints, and distributed session storage synchronization.

---

## 🏛️ Schema Architecture

### 1. Tables (`schema: runners`)
- **`runners.devices`**: Multi-tenant registry of enrolled physical workstations and cloud worker nodes with CPU/RAM metrics and hardware fingerprint.
- **`runners.browsers`**: Central cloud inventory of virtual anti-detect browser profiles (GoLogin/AdsPower standard) with deterministic hardware fingerprints (seed, OS, WebRTC, CPU/RAM, languages, proxies) and session storage pointers (`.zip`).
- **`runners.proxies`**: Multi-tenant pool of residential, datacenter, mobile, and SOCKS5 proxies with live latency tracking and health checking.
- **`runners.node_browsers`**: Registry of node-local browser profiles discovered on edge worker PCs.

### 2. Storage Bucket
- **`browser-profiles`**: Private Supabase Storage bucket (256MB limit per archive) storing compressed session snapshot archives (`<tenant_id>/<browser_id>.zip`).

### 3. Core RPC Procedures & PostgREST Facades
- **`runners.enroll_device(...)`**: Idempotent RPC endpoint for zero-touch device onboarding with secure token hashing.
- **`runners.heartbeat(...)`**: Telemetry and liveness RPC endpoint (also exposed as `public.heartbeat`).
- **`runners.acquire_browser(...)`**: Distributed lease acquisition with Optimistic Overwrite (Last-Write-Wins) and real-time In-Use Advisory Warning (also exposed as `public.acquire_browser`).
- **`runners.release_browser(...)`**: Session storage snapshot sync and transition back to `idle` (also exposed as `public.release_browser`).
- **`runners.create_browser(...)`**: Deterministic browser profile generation with PRNG seed and tenant verification (also exposed as `public.create_browser`).
- **`runners.list_browsers(...)`**: Secure tenant-scoped profile listing with device token authentication (also exposed as `public.list_browsers`).
- **`runners.reap_stale_browser_locks(...)`**: Data Engine Dead Lease Reaper that automatically frees browser locks when a workstation has stopped heartbeating (also exposed as `public.reap_stale_browser_locks`).
- **`runners.claim_proxy(...)`**: Atomically checks out an active proxy from the pool.
- **`runners.sync_proxies(...)`**: Batch syncs proxies from workstation into the tenant pool.

---

## 🔑 Permissions

| Permission ID | Module | Business Capability | Owner | Admin | Member |
|---|---|---|:---:|:---:|:---:|
| `runners:devices:read` | `runners` | View registered compute nodes and live telemetry | ✅ | ✅ | ✅ |
| `runners:devices:manage` | `runners` | Configure, pause, or remove runner devices | ✅ | ✅ | ❌ |
| `runners:devices:enroll` | `runners` | Enroll new physical workstations and edge nodes | ✅ | ✅ | ❌ |
| `runners:proxies:read` | `runners` | View proxy pool and health status within tenant | ✅ | ✅ | ✅ |
| `runners:proxies:manage` | `runners` | Create, edit, delete, and test proxies | ✅ | ✅ | ❌ |
| `runners:browsers:read` | `runners` | View virtual browser profiles and fingerprint configs | ✅ | ✅ | ✅ |
| `runners:browsers:manage` | `runners` | Create, update, launch, and control browser profiles | ✅ | ✅ | ✅ |

---

## 🚀 Lifecycle Management

### Installation
```powershell
# Via Plugin Pipeline Runner
.\scripts\plugins\apply_plugins.ps1 -Plugin runners -Action install -WithSeed
```

### Uninstallation
```powershell
# Clean uninstallation with zero dangling artifacts
.\scripts\plugins\apply_plugins.ps1 -Plugin runners -Action uninstall
```
