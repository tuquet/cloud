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
)

for test_file in "${TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        echo "[-] Error: Test file not found: $test_file" >&2
        exit 1
    fi

    echo ""
    echo "--> Running Test: $test_file"
    supabase db query "--$TARGET" -f "$test_file"
done

echo ""
echo "===================================================================="
echo " [ALL TESTS PASSED] Database integrity verified 100% successfully."
echo "===================================================================="
