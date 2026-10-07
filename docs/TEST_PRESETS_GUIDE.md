# Tuquet Cloud Test Presets & CLI Architecture Guide

This guide details the declarative Test Presets System and the `tuquet-test-cli` utility built for automated, reproducible end-to-end testing across **Tuquet Cloud**.

---

## 1. SOLID Architectural Design

The test preset subsystem is architected strictly under **SOLID principles** to eliminate ad-hoc, brittle database mocks:

```
tests/presets/
├── schema/
│   └── preset.schema.json      # [SRP] Declarative Contract Specification
├── sql/
│   └── 00_provision_helper.sql # [SRP] Atomic, Idempotent DB Provisioner Procedure
├── tunyk.json                  # [OCP] Production-ready Owner Identity Preset
└── collaborator.json           # [OCP] Standard Member Workspace Preset

scripts/testing/
├── tuquet-test-cli.ps1         # Native PowerShell CLI (Windows / Local Dev)
├── tuquet-test-cli.mjs         # Native Node.js CLI (Cross-platform / CI/CD)
└── tuquet-test-cli.sh          # POSIX Bash Wrapper
```

### Principles in Action:
- **Single Responsibility Principle (SRP)**:
  - **Presets Layer** (`tests/presets/*.json`): Pure data contracts specifying identities, tenants, plans, and roles. Zero execution logic.
  - **Database Provisioner** (`00_provision_helper.sql`): Encapsulates atomic DB transaction (`auth.users`, `auth.identities`, `public.profiles`, `public.tenants`, `public.tenant_members`, `public.member_roles`, `billing.subscriptions`).
  - **Verification Engine**: Dedicated authentication and PostgREST RLS assertion module.
  - **CLI Runner**: Handles CLI argument parsing, environment resolution, and formatted terminal reporting.
- **Open/Closed Principle (OCP)**:
  - Adding a new test scenario or identity requires **zero modifications** to existing code or SQL procedures. Simply drop a new `.json` file into `tests/presets/`!
- **Liskov Substitution Principle (LSP)**:
  - Both Local (`-Target local`) and Remote (`-Target linked`) environments adhere to the same execution contract.
- **Interface Segregation Principle (ISP)**:
  - Fine-grained subcommands: `list`, `apply`, `verify`, `provision-tenant`, and `cleanup` can each be called independently without running the entire pipeline.
- **Dependency Inversion Principle (DIP)**:
  - High-level test pipelines depend on the abstract declarative preset schema rather than low-level database connection specifics.

---

## 2. Default Test Presets

### `tunyk.json` (Owner Workspace Preset)
- **User Email**: `tunyk.93@gmail.com`
- **Password**: `Admin!12345`
- **Full Name**: `Nguyen Dang Tu`
- **State**: `ACTIVE 100%` (email confirmed, bcrypt hashed, GoTrue tokens initialized)
- **Tenant Slug**: `tunyk-workspace`
- **Tenant Name**: `Tunyk Enterprise Workspace`
- **Role**: `owner`
- **Plan**: `pro`

### `collaborator.json` (Member Preset)
- **User Email**: `collaborator@tuquet.dev`
- **Password**: `DevPass!12345`
- **Tenant Slug**: `collaborator-sandbox`
- **Role**: `member`
- **Plan**: `free`

---

## 3. CLI Usage

### A. List Available Presets
Displays all discovered presets in `tests/presets/`:

```powershell
# PowerShell
.\scripts\testing\tuquet-test-cli.ps1 list

# Node.js
node scripts/testing/tuquet-test-cli.mjs list
```

**Output:**
```
====================================================================
 [TUQUET-CLOUD-TEST-CLI] Available Test Presets
====================================================================
PRESET          EMAIL                          TENANT SLUG               ROLE     PLAN    
------------------------------------------------------------------------------------------
collaborator    collaborator@tuquet.dev        collaborator-sandbox      member   free    
tunyk           tunyk.93@gmail.com             tunyk-workspace           owner    pro     
```

---

### B. Apply Preset & Verify 100% Active State
Idempotently provisions the identity, creates the tenant, assigns membership/role, and verifies auth & RLS:

```powershell
# PowerShell
.\scripts\testing\tuquet-test-cli.ps1 apply -Preset tunyk -Verify

# Node.js
node scripts/testing/tuquet-test-cli.mjs apply --preset tunyk --verify
```

**Output:**
```
====================================================================
 [TUQUET-CLOUD-TEST-CLI] Applying Test Preset: tunyk
====================================================================
--> Provisioning Identity & Tenant in Database (local)...
    [OK] User ID:     7196a0b7-97a9-4d93-9e8c-ef1950b26b58
    [OK] Email:       tunyk.93@gmail.com
    [OK] Tenant ID:   491119bc-7c4e-47d6-83cd-c06e363500be
    [OK] Tenant Slug: tunyk-workspace
    [OK] Role:        owner
    [OK] Plan:        pro
    [OK] Status:      active

[APPLY SUCCESSFUL] Preset 'tunyk' applied successfully.

--> Verifying Authentication for: tunyk.93@gmail.com
    [OK] GoTrue Auth: HTTP 200 OK
    [OK] User ID: 7196a0b7-97a9-4d93-9e8c-ef1950b26b58
    [OK] Email Confirmed At: 09/25/2026 04:43:06
    [OK] Status: ACTIVE 100%
    [OK] Access Token (JWT): eyJhbGciOiJFUzI1NiIsImtpZCI6ImI4MTI...

--> Verifying Row-Level Security (RLS) & Tenant Isolation...
    [OK] Visible Tenants returned by PostgREST: 1
    [TARGET] Tenant: Tunyk Enterprise Workspace (slug: tunyk-workspace, status: active)

[VERIFICATION COMPLETE] Test Identity is 100% active, authenticated, and isolated via RLS!
```

---

### C. Standalone Auth & RLS Verification
Validate credentials against GoTrue (`/auth/v1/token?grant_type=password`) and PostgREST RLS:

```powershell
.\scripts\testing\tuquet-test-cli.ps1 verify -Preset tunyk
```

---

### D. Ad-hoc Tenant Provisioning
Quickly spin up a custom tenant for any identity:

```powershell
.\scripts\testing\tuquet-test-cli.ps1 provision-tenant `
    -Email tunyk.93@gmail.com `
    -Password 'Admin!12345' `
    -TenantSlug 'fleet-ops' `
    -TenantName 'Fleet Operations' `
    -Plan 'enterprise' `
    -Role 'owner' `
    -Verify
```

---

### E. Cleanup Preset
Removes the test user and their test tenant:

```powershell
.\scripts\testing\tuquet-test-cli.ps1 cleanup -Preset collaborator
```

---

## 4. How to Add a New Test Preset

1. Create a new JSON file under `tests/presets/<your-preset-name>.json`:
```json
{
  "$schema": "./schema/preset.schema.json",
  "name": "qa-tester",
  "description": "QA Automation Test Account",
  "user": {
    "email": "qa@tuquet.dev",
    "password": "TestPassword!123",
    "full_name": "QA Automation Bot",
    "avatar_url": "https://api.dicebear.com/7.x/identicon/svg?seed=qa"
  },
  "tenant": {
    "slug": "qa-workspace",
    "name": "QA Validation Workspace",
    "plan": "pro"
  },
  "role": "owner"
}
```
2. Run `.\scripts\testing\tuquet-test-cli.ps1 apply -Preset qa-tester -Verify`.
3. The preset is instantly usable across tests and manual development.
