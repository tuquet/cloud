# Project Agent Behavioral Rules: tuquet-cloud

## 1. Domain Terminology & Anti-Hallucination Standards
All AI agents operating in this repository MUST strictly adhere to [**`docs/terminology_dictionary.md`**](docs/terminology_dictionary.md):
- **Tenancy Boundary**: The canonical database entity is **`Tenant`** (`public.tenants`, `tenant_id`). NEVER name tables, columns, or foreign keys as `Workspace`, `Organization`, `Team`, or `Project`.
- **User vs Profile**: Identity is **`User`** (`auth.users`); public metadata is **`Profile`** (`public.profiles`). Never link foreign keys directly to `auth.users` from domain tables; always link to `public.profiles(id)`.
- **Role vs Permission**: Roles live in `public.roles`. Permissions are atomic strings `<module>:<resource>:<action>` in `public.permissions`. Permissions are NEVER assigned directly to users/members; they are mapped via `role_permissions` and assigned via `member_roles`.
- **Plugin Taxonomy**: Distinct autonomous database modules are **`Plugins`** (`public.system_plugins`). Distinct isolated schemas: `media`, `billing`, `events`, `automa`. Terms `Module`, `Extension`, or `Addon` are FORBIDDEN in database schema and backend documentation.
- **Storage vs Vault**: Cloud media storage is **`Storage`** (`media.assets`, bucket `tenant-assets`). The term `Vault` is FORBIDDEN in cloud services.
- **Automa Domain Terms**:
  - Execution Nodes: **`Runner`** (`automa.runners`). Terms `Worker` or `Bot` are FORBIDDEN.
  - Virtual Browsers: **`Browser`** (`*.browser.json`). Terms `Profile` or `Member` are FORBIDDEN in browser context.
  - Automation Graphs: **`Workflow`** (`automa.workflows`).
  - Runtime Dispatches: **`Campaign Run`** (`automa.campaign_runs`).
  - Telemetry Streams: **`Execution Log`** (`automa.execution_logs`).
- **Event Dispatch**: Use **`Transactional Outbox`** (`events.outbox`) and **`Webhooks`** (`events.subscriptions`, `events.deliveries`). Hallucinating external message brokers (Kafka, RabbitMQ, Redis BullMQ) is strictly FORBIDDEN.

## 2. PostgreSQL & Supabase Architecture Invariants
- **Base Kernel & Plugin Isolation**: Schema `public` is reserved strictly for Base Platform Core IAM. All on-demand features MUST reside in their dedicated isolated schemas (`media`, `billing`, `events`, `automa`).
- **O(1) RLS via Custom Access Token Hook**: Security policies MUST leverage claims (`tenant_id`, `roles`, `permissions`) injected into the JWT by `public.custom_access_token_hook`.
- **No-Recursion Pattern**: All security query helpers MUST be marked `SECURITY DEFINER` and `STABLE`.
- **CWE-426 Protection**: Every SQL function and trigger MUST declare `SET search_path = ''` and use fully-qualified object names (`public.profiles`, `auth.users`).

## 3. Scripting & Execution Standards
- **Strict ASCII Invariance:** All PowerShell and batch scripts in this repository MUST be strictly ASCII-encoded (no Vietnamese diacritics in code, comments, or output strings) to avoid Windows PowerShell 5.1 ANSI parsing issues.
- **Reserved Characters:** Always quote strings containing reserved shell characters (such as `&`, `|`, `<`, `>`).
- **Native Command Stderr Safety:** Always handle native CLI stderr streams safely when checking tool statuses.
