#!/usr/bin/env bash
# ============================================================================
# TUQUET-CLOUD DATABASE TEST RUNNER
# Description: Executes automated SQL verification suites against local Supabase
# ============================================================================

set -euo pipefail

TARGET="${1:-local}"

echo "===================================================================="
echo " [TUQUET-CLOUD] Database Test Suite Runner (Target: $TARGET)"
echo "===================================================================="

TEST_FILES=(
    "tests/db/01_verify_core_iam.sql"
    "tests/db/02_verify_automa_plugin.sql"
    "tests/db/02b_verify_runners_plugin.sql"
    "tests/db/03_verify_storage_plugin.sql"
    "tests/db/04_verify_subscriptions_plugin.sql"
    "tests/db/05_verify_webhooks_plugin.sql"
    "tests/db/06_verify_test_presets.sql"
)

# Ensure provision helper procedure is present for verification
HELPER_FILE="tests/presets/sql/00_provision_helper.sql"
if [[ -f "$HELPER_FILE" ]]; then
    if [[ "$TARGET" == "local" ]]; then
        DB_CONTAINER=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -n 1)
        if [[ -n "$DB_CONTAINER" ]]; then
            docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres < "$HELPER_FILE" > /dev/null 2>&1 || true
        else
            supabase db query "--$TARGET" -f "$HELPER_FILE" > /dev/null 2>&1 || true
        fi
    else
        supabase db query "--$TARGET" -f "$HELPER_FILE" > /dev/null 2>&1 || true
    fi
fi

for test_file in "${TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        echo "[-] Error: Test file not found: $test_file" >&2
        exit 1
    fi

    echo ""
    echo "--> Running Test: $test_file"
    if [[ "$TARGET" == "local" ]]; then
        DB_CONTAINER=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -n 1)
        if [[ -n "$DB_CONTAINER" ]]; then
            docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_file"
        else
            supabase db query "--$TARGET" -f "$test_file"
        fi
    else
        supabase db query "--$TARGET" -f "$test_file"
    fi
done

echo ""
echo "===================================================================="
echo " [ALL TESTS PASSED] Database integrity verified 100% successfully."
echo "===================================================================="
