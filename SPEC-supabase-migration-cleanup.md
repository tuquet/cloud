# Spec: Supabase Migration Consolidation & Cleanup (KISS & YAGNI)

## Objective
Apply **KISS** (Keep It Simple, Stupid) and **YAGNI** (You Aren't Gonna Need It) to clean up `cloud/supabase/migrations`. The project is currently in early boilerplate development; premature features, duplicate seeds, and rollback anti-patterns will be eliminated to establish a single, canonical, rock-solid Core IAM baseline migration.

### Context & Decisions
1. **Premature Inbox / OTP Subsystem (YAGNI):** The inbox and OTP interception feature (`inbox.domains`, `inbox.emails`, `inbox.otps`, `inbox.links`, etc.) has not been developed on the client/runner side yet. Including it now is premature. Both `20261013000001_inbox_email_and_otp_subsystem.sql` and the anti-pattern `rollback_inbox_subsystem.sql` (along with tests `07_verify_inbox_subsystem.sql` and `test_acceptance_inbox.mjs`) will be completely removed.
2. **Duplicate Admin Seed Migration (KISS):** `20261011175500_seed_admin_tuquet.sql` is a duplicate seed script disguised as a DDL migration. `supabase/seed.sql` already provisions `admin@tuquet.com`, `Tuquet Enterprise Corp` tenant, profiles, and identities. This migration will be removed.
3. **Canonical Relocation of Dynamic Bank Pool (SRP & Plugin Architecture):** Table `billing.bank_receiving_accounts` belongs to schema `billing` owned by the `subscriptions` plugin. It will be integrated into `supabase/plugins/subscriptions/install.sql` (and `uninstall.sql`), and `20261017000001_billing_dynamic_bank_pool.sql` will be deleted.
4. **Baseline Migration State:** `cloud/supabase/migrations/` will contain exactly **one** clean baseline migration: `20261011000001_core_iam.sql`.

---

## Tech Stack
- **Database:** PostgreSQL 15+ (Supabase)
- **Tooling:** Supabase CLI, psql, Docker
- **Target Repository:** `cloud/` (`tuquet-cloud`)

---

## Commands
Full executable commands for development and verification:

```powershell
# Reset local database schema (runs the single canonical migration cleanly)
supabase db reset --local --no-seed

# Full reset with plugins, seeds, and verification tests via project orchestrator
.\scripts\reset_db.ps1 -Target local -WithPlugins -WithSeed -WithTests

# Run database automated verification test suite
.\scripts\test_db.ps1 -Target local
```

---

## Project Structure
Target directories and affected files:

```text
cloud/
├── supabase/
│   ├── migrations/
│   │   ├── 20261011000001_core_iam.sql                     # Single Canonical Core IAM Migration
│   │   ├── 20261011175500_seed_admin_tuquet.sql            # [DELETE] (Already in seed.sql)
│   │   ├── 20261013000001_inbox_email_and_otp_subsystem.sql  # [DELETE] (Premature YAGNI)
│   │   ├── 20261017000001_billing_dynamic_bank_pool.sql    # [DELETE] (Relocated to subscriptions plugin)
│   │   └── rollback_inbox_subsystem.sql                    # [DELETE] (Anti-pattern)
│   ├── plugins/
│   │   └── subscriptions/
│   │       ├── install.sql                                 # Append billing.bank_receiving_accounts
│   │       └── uninstall.sql                               # Add teardown for bank_receiving_accounts
│   └── seed.sql                                            # Verified SSOT for seed data
├── scripts/
│   └── test_acceptance_inbox.mjs                           # [DELETE] (Premature YAGNI)
└── tests/
    └── db/
        └── 07_verify_inbox_subsystem.sql                   # [DELETE] (Premature YAGNI)
```

---

## Code Style & Schema Invariants
All database code must adhere to `cloud/AGENTS.md`:
1. **CWE-426 Protection:** Functions declare `SET search_path = ''` with fully-qualified names.
2. **Tenancy Boundary:** The canonical entity is strictly `Tenant` (`public.tenants`, `tenant_id`).
3. **Plugin Isolation:** Core platform lives in `public`. SaaS subscriptions and payments live in `billing` schema within `supabase/plugins/subscriptions/`.
4. **Clean DDL:** DDL migrations must contain schema structure only; no test credentials or mutable seed users.

---

## Testing Strategy
- **Migration Execution:** `supabase db reset --local --no-seed` applies cleanly without warnings or errors.
- **Plugin Orchestration:** `.\scripts\reset_db.ps1 -Target local` successfully applies core IAM, all plugins (including updated `subscriptions`), and standard Model 1 seed data.
- **Regression Tests:** All active test suites in `tests/db/` (`01_verify_core_iam.sql` through `06_verify_test_presets.sql`, `08_verify_commerce_plugin.sql`) pass.

---

## Boundaries
- **Always:**
  - Verify that `supabase/seed.sql` retains `admin@tuquet.com` and credentials.
  - Delete `rollback_inbox_subsystem.sql` and premature inbox files.
  - Integrate `billing.bank_receiving_accounts` with appropriate RLS policies into `subscriptions/install.sql`.
- **Ask First:**
  - Introducing any new schemas outside `public` or approved plugin schemas.
- **Never:**
  - Keep loose, non-timestamped `.sql` files or rollback scripts in `supabase/migrations/`.
  - Leave broken foreign keys or references to dropped schemas.

---

## Success Criteria
1. `cloud/supabase/migrations/` contains only `20261011000001_core_iam.sql`.
2. `rollback_inbox_subsystem.sql`, `20261013000001_inbox_email_and_otp_subsystem.sql`, `20261011175500_seed_admin_tuquet.sql`, and `20261017000001_billing_dynamic_bank_pool.sql` are deleted.
3. `billing.bank_receiving_accounts` is cleanly defined in `supabase/plugins/subscriptions/install.sql` (and dropped in `uninstall.sql`).
4. `tests/db/07_verify_inbox_subsystem.sql` and `scripts/test_acceptance_inbox.mjs` are removed.
5. `.\scripts\reset_db.ps1` runs without errors.
