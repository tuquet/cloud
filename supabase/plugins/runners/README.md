# ⚡ Tuquet Cloud Plugin: Runners & Compute Fleet

**Plugin ID:** `runners`  
**Schema:** `runners`  
**Version:** `1.0.0`

## 📖 Overview
The `runners` plugin acts as the universal compute infrastructure foundation for Tuquet Cloud. It manages physical workstations, edge nodes, and cloud runner daemons running `runner` (Runner in Rust).

## 🏛️ Schema Architecture
- **`runners.devices`**: Multi-tenant registry of enrolled physical workstations and cloud worker nodes.
- **`runners.node_browsers`**: Central inventory of node-local browser profiles hosted by worker PCs.
- **`runners.proxies`**: Central pool of residential, datacenter, mobile, and SOCKS5 proxies managed per tenant with latency tracking and dynamic assignment.
- **`runners.enroll_device(...)`**: Idempotent RPC endpoint for zero-touch device onboarding.
- **`runners.heartbeat(...)`**: Telemetry and liveness RPC endpoint.
- **`runners.report_browser_inventory(...)`**: Syncs node-local browser profiles to the central cloud hub.
- **`runners.report_proxy_health(...)`**: Reports latency, health status, and errors for proxies.
- **`runners.claim_proxy(...)`**: Atomically checks out an active proxy from the pool for a device or browser.
- **`runners.sync_proxies(...)`**: Batch syncs proxies from workstation into the central tenant pool.

## 🔑 Permissions
- `runners:devices:read`: View registered nodes and live status.
- `runners:devices:manage`: Pause, configure, or retire nodes.
- `runners:devices:enroll`: Enroll new physical workstations into the tenant fleet.
- `runners:proxies:read`: View proxy pool and health telemetry within tenant.
- `runners:proxies:manage`: Create, update, delete, and assign proxies within tenant.
