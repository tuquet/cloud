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
- **Base Kernel & Plugin Isolation**: Schema `public` is reserved strictly for the Base Platform Core IAM. All on-demand features MUST reside in their dedicated isolated schemas (`media`, `billing`, `events`, `automa`).
- **FORBIDDEN Monolithic Coupling**: Agents MUST NEVER inject plugin tables into the `public` schema or draw monolithic static ERD diagrams that combine plugin tables with the Core Kernel ERD. All plugin-specific ERDs MUST reside exclusively inside their own `supabase/plugins/<plugin_id>/README.md`.
- **O(1) RLS via Custom Access Token Hook**: Security policies MUST leverage claims (`tenant_id`, `roles`, `permissions`) injected into the JWT by `public.custom_access_token_hook`. Never write circular subqueries on `tenant_members` in RLS policies.
- **No-Recursion Pattern**: All security query helpers MUST be marked `SECURITY DEFINER` and `STABLE`.
- **CWE-426 Protection**: Every SQL function, procedure, and trigger MUST declare `SET search_path = ''` and use fully-qualified object names (`public.profiles`, `auth.users`).

## 3. Scripting & Execution Standards
- **Strict ASCII Invariance:** All PowerShell and batch scripts in this repository MUST be strictly ASCII-encoded (no Vietnamese diacritics in code, comments, or output strings) to avoid Windows PowerShell 5.1 ANSI parsing issues.
- **Reserved Characters:** Always quote strings containing reserved shell characters (such as `&`, `|`, `<`, `>`).
- **Native Command Stderr Safety:** Always handle native CLI stderr streams safely when checking tool statuses.

## 4. SOLID Documentation Architecture & Single Source of Truth (SSOT)
To eliminate documentation drift and prevent stale specifications across repos:
- **Single Responsibility Principle (SRP)**:
  - Root `README.md` is an Architectural Facade, Quickstart, and Central Routing Hub. It MUST NOT duplicate database table definitions, column types, or plugin implementation details.
  - `docs/architecture.md` is the authoritative source for system architecture, Kernel ERD, and universal extension contracts.
  - `docs/terminology_dictionary.md` is the authoritative lexicon for entity definitions and naming rules.
  - `supabase/plugins/<plugin_id>/README.md` is the exclusive single source of truth for that plugin's schema, tables, RLS policies, permissions, and lifecycle.
- **Single Source of Truth (SSOT / DRY)**: Never copy-paste table definitions or schemas across files. Always use hyperlinked references to the single authoritative document.
- **Open/Closed Principle (OCP)**: Adding or extending a plugin should only require adding a reference row in the catalog router of `README.md` and `docs/architecture.md`, never modifying or polluting existing core documentation.
