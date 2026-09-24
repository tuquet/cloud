# Terminology Dictionary & Anti-Hallucination Lexicon

> **Supreme Purpose**: This document serves as the **Single Source of Truth (SSOT)** for all technical terminology, domain entities, database naming conventions, and architectural contracts within `tuquet-cloud` and across the broader Tuquet ecosystem (`tuquet-lib`, `tuquet-automa`, `tuquet-cloud`, `tuquet-scoop-bucket`).  
> All technical documentation, SQL routines, migrations, API DTOs, client SDK code, and AI Agents **MUST adhere 100%** to this lexicon to completely eradicate **Terminology Hallucination** and ambiguous concept mixing.

---

## 1. The 5 Golden Rules of Terminology Invariance

1. **One Concept - One Canonical Identifier**: Every technical entity possesses exactly one standardized identifier in database schemas and documentation. Never use informal synonyms interchangeably for the same table, column, or architecture boundary.
2. **Zero Forbidden Terms**: Any terms designated as forbidden or ambiguous in the Lexicon Matrix MUST NEVER appear in SQL schemas, API DTOs, or architectural documentation.
3. **Data Layer vs Presentation Layer Separation**: Database entity identifiers (`tenants`, `profiles`, `runners`) are immutable. User-facing display labels (e.g., "Workspace", "Company", "Worker Node") belong strictly to the UI Presentation Layer and must always cite the underlying canonical database entity in technical documentation.
4. **Transparent Casing & Key Conventions**:
   - PostgreSQL Schemas: lowercase singular `snake_case` (`public`, `media`, `billing`, `events`, `automa`).
   - PostgreSQL Tables: lowercase plural `snake_case` (`tenants`, `profiles`, `roles`, `permissions`, `assets`, `plans`, `workflows`, `runners`).
   - Primary Keys: always named `id`. Foreign keys referencing `<table>`: always named `<table>_id` (e.g. `tenant_id`, `user_id`, `role_id`, `workflow_id`).
5. **Standardized Capability Permissions**: All atomic permission codes (`permission_id`) MUST strictly adhere to the 3-segment convention: `<module>:<resource>:<action>` (e.g. `automa:campaigns:run`, `media:assets:upload`, `billing:plans:view`).

---

## 2. Canonical Lexicon Matrix

Use this quick-reference matrix for anti-hallucination audits during documentation authoring or coding:

| Canonical Term | Database Schema & Table | Forbidden / Ambiguous Terms | Architectural Scope & Technical Invariant |
| :--- | :--- | :--- | :--- |
| **`Tenant`** | `public.tenants` (`tenant_id`) | ❌ *Organization*, *Workspace*, *Account*, *Team*, *Project* | Root multi-tenancy isolation boundary. Every child domain table anchors to `tenant_id`. |
| **`User`** | `auth.users` | ❌ *Account*, *Person*, *Client* | Identity entity managed internally by Supabase Auth (email, password hash, OAuth metadata). |
| **`Profile`** | `public.profiles` | ❌ *User Metadata*, *Account Info*, *Browser Profile* | Public user record synchronized 1:1 with `auth.users` via a database trigger. |
| **`Tenant Member`** | `public.tenant_members` | ❌ *User*, *Profile*, *Employee*, *Team Member* | Association link binding a User `Profile` to a `Tenant`, with active/suspended membership state. |
| **`Role`** | `public.roles` | ❌ *Group*, *Tier*, *Level*, *Permission Set* | Named role entity: System Roles (`is_system = true`, `tenant_id IS NULL`) or Custom Tenant Roles. |
| **`Permission`** | `public.permissions` | ❌ *Right*, *Privilege*, *Capability*, *Scope* | Atomic capability string formatted as `<module>:<resource>:<action>` (e.g. `tenants:update`). |
| **`Member Role`** | `public.member_roles` | ❌ *User Role*, *Role Assignment* | Many-to-many bridge assigning roles to a tenant member within a specific tenant. |
| **`Plugin`** | `public.system_plugins` | ❌ *Module*, *Extension*, *Addon*, *Package* | Autonomous database module with a dedicated folder `supabase/plugins/<id>/` and PostgreSQL schema. |
| **`Storage`** | `media.assets` & `tenant-assets` | ❌ *Vault*, *Media Bucket*, *File Drive* | Cloud media asset storage service. The term "Vault" is **FORBIDDEN** in cloud services. |
| **`Browser`** | `automa.runners` / `*.browser.json` | ❌ *Profile*, *Browser Profile*, *Anti-detect Profile* | Isolated anti-detect virtual browser container. Calling a browser instance a "Profile" is **FORBIDDEN**. |
| **`Runner`** | `automa.runners` | ❌ *Worker*, *Agent Node*, *Bot*, *Client Daemon* | Execution workstation node (Desktop OS or Cloud VPS running the Rust daemon from `apps/core`). |
| **`Workflow`** | `automa.workflows` | ❌ *Script*, *Flowchart*, *Automation Pipeline* | Visual node graph AST automation workflow compatible with VueFlow graph JSON. |
| **`Campaign Run`** | `automa.campaign_runs` | ❌ *Batch Job*, *Execution*, *Run Task* | Execution session of an automation campaign dispatched across distributed runners. |
| **`Execution Log`** | `automa.execution_logs` | ❌ *Audit Log*, *System Log*, *Trace File* | Telemetry stream recording block-level execution events during an automation run. |
| **`Transactional Outbox`**| `events.outbox` | ❌ *Message Queue*, *Kafka Stream*, *RabbitMQ* | Pure PostgreSQL ACID-compliant event outbox for reliable asynchronous webhook dispatching. |
| **`Usage Meter`** | `billing.usage_meters` | ❌ *Quota Counter*, *Metric Tracker* | Real-time gauge measuring resource consumption within the current billing cycle. |

---

## 3. Domain Invariants & Detailed Boundaries

### 3.1. Identity & Multi-Tenant IAM (Kernel Domain)

```
[auth.users] (Supabase Auth)
     │ (1:1 Trigger Sync)
     ▼
[public.profiles] ◄──────┐
     │                   │
     │ joins             │ creates
     ▼                   │
[public.tenant_members] ─┴──► [public.tenants] (Root Multi-Tenant Boundary)
     │                             │
     │ assigned                    │ owns
     ▼                             ▼
[public.member_roles] ◄────── [public.roles]
                                   │
                                   │ grants
                                   ▼
                             [public.role_permissions] ◄── [public.permissions]
```

1. **`Tenant` (`public.tenants`)**:
   - Represents an organization, workspace, or enterprise subscribing to the SaaS platform.
   - Primary isolation boundary: Every business entity across all plugins anchors to `tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE`.
   - Never replace `Tenant` with `Workspace` or `Project` in database schemas or API contracts.
2. **`User` vs `Profile`**:
   - **`User` (`auth.users`)**: Governed internally by Supabase Auth (auth credentials, hashed passwords, verification timestamps). Application code must NEVER query `auth.users` directly in business logic.
   - **`Profile` (`public.profiles`)**: Public entity in the `public` schema. Synchronized 1:1 with `auth.users.id`. Contains extended metadata: `full_name`, `avatar_url`, `updated_at`.
   - Invariant: All domain tables referencing user identity must point foreign keys to `public.profiles(id)`.
3. **`Tenant Member` (`public.tenant_members`)**:
   - Explicit membership link connecting a User Profile to a Tenant.
   - A single User can hold memberships across multiple Tenants with independent states (`active`, `suspended`).
4. **`Role` vs `Permission`**:
   - Roles group permissions together. Two distinct role types:
     - **System Roles**: Global defaults where `tenant_id IS NULL` and `is_system = true` (`owner`, `admin`, `member`, `viewer`).
     - **Custom Tenant Roles**: Created by tenant administrators where `tenant_id = UUID` and `is_system = false`.
   - Permissions are atomic strings `<module>:<resource>:<action>` in `public.permissions`.
   - Invariant: Permissions are NEVER assigned directly to users or members. Permissions are granted to Roles via `role_permissions`, and Roles are assigned to Members via `member_roles`.
5. **`Custom Access Token Hook` (`public.custom_access_token_hook`)**:
   - Hook invoked by Supabase Auth upon issuing JWT tokens.
   - Injects active `tenant_id`, `roles`, and atomic `permissions` (capped at **25 items**) into `app_metadata`.
   - Enables **$O(1)$** RLS policy evaluation without circular subqueries.
6. **`Audit Log` (`public.audit_logs`)**:
   - Immutable security trail. Primary key is `BIGINT GENERATED ALWAYS AS IDENTITY`, client IP is stored as `INET`, and `tenant_id` enables future declarative partitioning.

---

### 3.2. Modular Plugin Architecture (Plugin Domain)

```
[public.system_plugins] (Master Lifecycle Registry)
        │
        ├── 'core-iam'       ──► Schema: public    (Kernel Flag: is_system = true)
        ├── 'storage'        ──► Schema: media     (On-demand Plugin)
        ├── 'subscriptions'  ──► Schema: billing   (On-demand Plugin)
        ├── 'webhooks'       ──► Schema: events    (On-demand Plugin)
        └── 'automa'         ──► Schema: automa    (On-demand Plugin)
```

1. **`Plugin` (`public.system_plugins`)**:
   - Self-contained, autonomous database module residing in its own dedicated PostgreSQL schema.
   - Never refer to database plugins as "Extensions", "Modules", or "Addons".
2. **Standard Plugin Directory Structure**:
   Every plugin in `supabase/plugins/<plugin_id>/` must contain exactly 4 files:
   - `plugin.json`: Manifest declaring `id`, `name`, `version`, `schema`, `dependencies`, `tables`, `permissions`.
   - `install.sql`: DDL/DML creating isolated schema, tables, indexes, RLS policies, and registry entry.
   - `uninstall.sql`: DDL dropping schema and unregistering cleanly from `system_plugins`.
   - `README.md`: Domain-specific documentation and internal ERD.
3. **`is_system` Immutability Guard**:
   - Plugins marked with `is_system = true` (e.g. `core-iam`) are kernel foundations and cannot be uninstalled.
4. **Topological Installation Order**:
   - `storage` (Storage Infrastructure) $\rightarrow$ `subscriptions` (Billing & Quota) $\rightarrow$ `webhooks` (Event Outbox) $\rightarrow$ `automa` (Domain Workflows). Automated via `scripts/plugins/apply_plugins.ps1`.

---

### 3.3. Storage & Media Assets Domain

1. **`Storage` (Never Use "Vault")**:
   - Cloud media asset storage service backed by the Supabase Storage Engine.
   - The term "Vault" is strictly **FORBIDDEN** for cloud storage. "Vault" only exists in `tuquet-automa` referring to the offline local scenario directory (`apps/vault`).
2. **`Media Asset` (`media.assets`)**:
   - File metadata catalog: `file_path`, `mime_type`, `file_size_bytes`, `metadata JSONB`.
   - Schema: Resides in schema `media` (preventing collision with Supabase's internal `storage` schema).
3. **`Dual-Layer Storage RLS`**:
   - Layer 1: Object storage RLS on `storage.objects` enforcing path isolation `(storage.foldername(name))[1]::uuid = active_tenant_id`.
   - Layer 2: Metadata catalog RLS on `media.assets` enforcing row-level access control.

---

### 3.4. Subscriptions & Quota Metering Domain

1. **`Plan` (`billing.plans`)**:
   - SaaS pricing tiers (`free`, `pro`, `enterprise`).
   - Quota limits: `max_members`, `max_storage_mb`, `max_monthly_runs`.
2. **`Subscription` (`billing.subscriptions`)**:
   - Active subscription state for a tenant (`tenant_id UNIQUE`).
   - States: `free_tier`, `trialing`, `active`, `past_due`, `canceled`, `unpaid`.
3. **`Usage Meter` (`billing.usage_meters`)**:
   - Consumption meter tracked by composite key `(tenant_id, metric_name)` (e.g., `storage_mb`, `monthly_runs`).
4. **Atomic Quota Functions**:
   - `billing.check_quota_available(_tenant_id, _metric, _increment)`: Returns BOOLEAN.
   - `billing.record_usage(_tenant_id, _metric, _amount)`: Atomically increments usage.

---

### 3.5. Transactional Outbox & Webhooks Domain

1. **`Transactional Outbox` (`events.outbox`)**:
   - Reliable event queue written within the same ACID database transaction as business mutations.
   - Hallucinating external message brokers (Kafka, RabbitMQ, Redis BullMQ) is strictly **FORBIDDEN**. The system uses pure PostgreSQL with a partial index `WHERE status = 'pending'`.
2. **`Webhook Subscription` (`events.subscriptions`)**:
   - External webhook endpoints configured per tenant (`target_url`, `secret_hash`, `is_active`).
3. **`Webhook Delivery` (`events.deliveries`)**:
   - Audit log recording HTTP dispatch attempts, response status codes, latencies, and error payloads.

---

### 3.6. Distributed Automa Cloud Bridge Domain

1. **`Workflow` (`automa.workflows`)**:
   - Visual automation graph AST JSON compatible with VueFlow and Chrome Extension runners.
2. **`Runner` (`automa.runners`)**:
   - Execution machine node (Desktop Workstation or Cloud VPS running the Axum daemon).
   - Calling runners "Workers", "Bots", or "Agent Nodes" is strictly **FORBIDDEN**.
3. **`Browser` (Anti-Detect Browser Invariant)**:
   - Isolated browser environment (`*.browser.json`) with distinct fingerprint, proxy, cookie jar, and local storage.
   - Invariant: Calling an anti-detect browser instance a "Profile" is strictly **FORBIDDEN** to prevent confusion with `public.profiles`.
4. **`Campaign Run` (`automa.campaign_runs`)**:
   - Execution session dispatching an automation workflow across one or more runners.
5. **`Execution Log` (`automa.execution_logs`)**:
   - Real-time telemetry log stream generated by block executions during a campaign run.

---

## 4. Technical Naming & Casing Conventions

| Entity | Casing Standard | Valid Example | Invalid Example |
| :--- | :--- | :--- | :--- |
| **PostgreSQL Schema** | `snake_case`, singular noun | `public`, `media`, `billing`, `events`, `automa` | `MediaSchema`, `medias`, `billing_v1` |
| **PostgreSQL Table** | `snake_case`, plural noun | `tenants`, `profiles`, `roles`, `assets`, `campaign_runs` | `tenant`, `tbl_profiles`, `TenantMember` |
| **PostgreSQL Column** | `snake_case` | `tenant_id`, `created_at`, `is_installed`, `file_size_bytes` | `tenantId`, `createdDate`, `IsSystem` |
| **Primary Key** | Always named `id` | `id UUID PRIMARY KEY`, `id BIGINT GENERATED ALWAYS AS IDENTITY` | `tenant_id PK`, `profile_id PK`, `uuid` |
| **Foreign Key** | `<table>_id` | `tenant_id REFERENCES public.tenants(id)` | `id_tenant`, `tenant_ref`, `fk_tenant` |
| **Function Name** | `snake_case`, verb prefix | `get_user_tenant_ids()`, `has_permission()`, `record_usage()` | `UserTenants()`, `checkPermission()`, `fn_usage` |
| **Permission Code** | `<module>:<resource>:<action>` | `automa:campaigns:run`, `media:assets:delete`, `tenants:read` | `RUN_CAMPAIGN`, `can_delete_media`, `admin` |
| **Plugin Folder** | `kebab-case` or `lowercase` | `core-iam`, `storage`, `subscriptions`, `webhooks`, `automa` | `PluginStorage`, `01_storage`, `sub_scripts` |

---

## 5. Authoring Pre-Flight Checklist (Anti-Hallucination Audit)

Before committing documentation, migrations, or code, authors and AI Agents **MUST verify this 10-point checklist**:

- [ ] **1. Tenant Check**: Did I avoid using `Workspace`, `Organization`, `Team`, or `Project` as table or column names instead of `Tenant` / `tenant_id`?
- [ ] **2. User vs Profile Check**: Did I point foreign keys to `public.profiles(id)` instead of referencing `auth.users` directly in business logic?
- [ ] **3. Role vs Permission Check**: Are permissions formatted as `<module>:<resource>:<action>` and mapped via `role_permissions` rather than assigned directly to users?
- [ ] **4. Plugin Taxonomy Check**: Are new features placed in their own isolated PostgreSQL schema rather than polluting `public`?
- [ ] **5. Vault Term Check**: In cloud storage context, did I use `Storage` / `media.assets` and completely eliminate the term `Vault`?
- [ ] **6. Browser vs Profile Check**: In automation context, did I refer to anti-detect browsers as `Browser` instead of `Profile`?
- [ ] **7. Runner Check**: Did I refer to execution nodes as `Runner` (`automa.runners`) instead of `Worker` or `Bot`?
- [ ] **8. Outbox Check**: Is asynchronous event dispatching modeled as a `Transactional Outbox` (`events.outbox`) without hallucinating external message brokers?
- [ ] **9. CWE-426 Check**: Does every SQL function and procedure declare `SET search_path = ''` with fully-qualified schema object names?
- [ ] **10. PostgREST API Check**: Did I avoid creating static JSON specification files and rely on live OpenAPI introspection at `/rest/v1/`?
