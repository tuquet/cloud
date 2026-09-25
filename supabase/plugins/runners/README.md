# ⚡ Tuquet Cloud Plugin: Runners & Compute Fleet

**Plugin ID:** `runners`  
**Schema:** `runners`  
**Version:** `1.0.0`

## 📖 Overview
The `runners` plugin acts as the universal compute infrastructure foundation for Tuquet Cloud. It manages physical workstations, edge nodes, and cloud runner daemons running `tqr` (Tuquet Runner in Rust).

## 🏛️ Schema Architecture
- **`runners.devices`**: Multi-tenant registry of enrolled physical workstations and cloud worker nodes.
- **`runners.enroll_device(...)`**: Idempotent RPC endpoint for zero-touch device onboarding.
- **`runners.heartbeat(...)`**: Telemetry and liveness RPC endpoint.

## 🔑 Permissions
- `runners:devices:read`: View registered nodes and live status.
- `runners:devices:manage`: Pause, configure, or retire nodes.
- `runners:devices:enroll`: Enroll new physical workstations into the tenant fleet.
