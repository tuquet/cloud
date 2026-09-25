#!/usr/bin/env bash
# ============================================================================
# TUQUET-CLOUD PLUGIN RUNNER UTILITY (BASH / LINUX / CI)
# Description: Automates the atomic installation of plugins in the canonical
#              architectural order against local or linked Supabase databases.
# ============================================================================

set -euo pipefail

TARGET="${1:-local}"
PLUGIN="${2:-all}"
WITH_SEED="${3:-true}"

CANONICAL_PLUGINS=(
    "storage:supabase/plugins/storage/install.sql:Media Storage Assets (schema: media)"
    "subscriptions:supabase/plugins/subscriptions/install.sql:Subscriptions & Quota (schema: billing)"
    "webhooks:supabase/plugins/webhooks/install.sql:Asynchronous Outbox & Webhooks (schema: events)"
    "automa:supabase/plugins/automa/install.sql:Automa Cloud Bridge (schema: automa)"
)

echo "===================================================================="
echo " [TUQUET-CLOUD] Plugin Pipeline Runner (Target: $TARGET)"
echo "===================================================================="

for item in "${CANONICAL_PLUGINS[@]}"; do
    IFS=":" read -r plugin_id install_file desc <<< "$item"

    if [[ "$PLUGIN" != "all" && "$PLUGIN" != "$plugin_id" ]]; then
        continue
    fi

    if [[ ! -f "$install_file" ]]; then
        echo "[-] Error: Plugin install file not found: $install_file" >&2
        exit 1
    fi

    echo ""
    echo "--> Installing Plugin: [$plugin_id] - $desc"
    supabase db query "--$TARGET" -f "$install_file"
    echo "    [OK] Successfully applied $install_file"

    if [[ "$plugin_id" == "automa" && "$WITH_SEED" == "true" ]]; then
        seed_file="supabase/plugins/automa/seed.sql"
        if [[ -f "$seed_file" ]]; then
            echo "    --> Applying sample data: $seed_file"
            supabase db query "--$TARGET" -f "$seed_file"
            echo "    [OK] Sample data applied for automa"
        fi
    fi
done

echo ""
echo "===================================================================="
echo " [SUCCESS] All targeted plugins have been installed successfully."
echo "===================================================================="
