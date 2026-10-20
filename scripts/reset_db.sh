#!/usr/bin/env bash
# ============================================================================
# TUQUET-CLOUD DATABASE RESET & PROVISIONING ORCHESTRATOR (BASH / LINUX / CI)
# Description: Resets Supabase database (local Docker or linked Cloud project),
#              runs foundational migrations, applies canonical plugins in order,
#              and seeds Model 1 standard QA test data.
# ============================================================================

set -euo pipefail

TARGET="${1:-local}"
WITH_PLUGINS="${2:-true}"
WITH_SEED="${3:-true}"
WITH_TESTS="${4:-false}"
FORCE="${5:-false}"
PROJECT_REF="dswhacsoaxgpfnkaxnhz"

echo "===================================================================="
echo " [TUQUET-CLOUD] Database Reset & Provisioning Orchestrator (Target: $TARGET)"
echo "===================================================================="

if [ "$TARGET" != "local" ]; then
    echo -e "\n[DANGER] WARNING: You are targeting a REMOTE Supabase database ($PROJECT_REF)!"
    echo "This operation will completely DROP all data, schemas, and tables on Supabase Cloud."
    
    if [ "$FORCE" != "true" ]; then
        read -rp "Are you sure you want to completely RESET the remote database? (Type 'RESET' to confirm): " CONFIRM
        if [ "$CONFIRM" != "RESET" ]; then
            echo "[ABORTED] Reset cancelled by user. No changes were made."
            exit 0
        fi
    fi

    if [ -z "${HTTP_PROXY:-}" ]; then
        export HTTP_PROXY="http://127.0.0.1:8118"
        export HTTPS_PROXY="http://127.0.0.1:8118"
    fi
    echo "Routing traffic via Bridge HTTP Forwarder ($HTTP_PROXY)..."
fi

echo -e "\n--> Step 1/4: Resetting database schema and migrations..."
if [ "$TARGET" = "local" ]; then
    supabase db reset --local --no-seed
else
    supabase db reset --linked --no-seed --yes
fi
echo "    [OK] Database core migrations applied successfully."

if [ "$WITH_PLUGINS" = "true" ]; then
    echo -e "\n--> Step 2/4: Applying canonical plugins..."
    bash scripts/plugins/apply_plugins.sh "$TARGET" all install false
    echo "    [OK] Plugins applied successfully."
fi

if [ "$WITH_SEED" = "true" ]; then
    echo -e "\n--> Step 3/4: Seeding Model 1 test data..."
    if [ "$TARGET" = "local" ]; then
        docker exec -i supabase_db_cloud psql -U postgres -d postgres < supabase/seed.sql
    else
        supabase db query --linked -f supabase/seed.sql
    fi
    echo "    [OK] Seed data applied successfully."
fi

if [ "$WITH_TESTS" = "true" ]; then
    echo -e "\n--> Step 4/4: Running verification tests..."
    bash scripts/test_db.sh "$TARGET"
fi

echo -e "\n===================================================================="
echo " [SUCCESS] Database reset and initialization complete for target: $TARGET"
echo " Universal Test Password: Tuquet1102@"
echo "===================================================================="
