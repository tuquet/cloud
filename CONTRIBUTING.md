# Contributing to tuquet/cloud

Tuquet Cloud is the centralized Supabase control plane (multi-tenant isolation,
realtime event dispatch, and telemetry foundation).

## Project

The authoritative architecture, terminology, and plugin documentation live at
[docs.tuquet.com/en/cloud](https://docs.tuquet.com/en/cloud/); read it before
changing schemas or RLS policies.

## Running tests

Database verification suites run against a local Supabase instance:

```bash
bash scripts/test_db.sh local
```

Acceptance / CLI smoke runners: `scripts/testing/tuquet-test-cli.sh`,
`scripts/test_acceptance_realtime.mjs`, `scripts/test_acceptance_automation.mjs`.

## Pull requests

- Keep commits atomic and scoped to a single concern.
- Never force-push to `main`.
- Describe the change and its motivation in the PR body.
