#!/usr/bin/env bash
# ============================================================================
# TUQUET-CLOUD PLUGIN RUNNER UTILITY (BASH / LINUX / CI)
# Description: Automates atomic installation & uninstallation of plugins
#              in canonical architectural order against local or linked Supabase.
# ============================================================================

set -euo pipefail

TARGET="${1:-local}"
PLUGIN="${2:-all}"
ACTION="${3:-install}"
WITH_SEED="${4:-true}"

echo "===================================================================="
echo " [TUQUET-CLOUD] Plugin Pipeline Runner (Action: $ACTION, Target: $TARGET)"
echo "===================================================================="

if [[ "$ACTION" == "uninstall" ]]; then
    CANONICAL_PLUGINS=(
        "automa:supabase/plugins/automa/uninstall.sql:Automa Cloud Bridge (schema: automa)"
        "runners:supabase/plugins/runners/uninstall.sql:Runners & Compute Fleet (schema: runners)"
        "webhooks:supabase/plugins/webhooks/uninstall.sql:Asynchronous Outbox & Webhooks (schema: events)"
        "subscriptions:supabase/plugins/subscriptions/uninstall.sql:Subscriptions & Quota (schema: billing)"
        "storage:supabase/plugins/storage/uninstall.sql:Media Storage Assets (schema: media)"
    )
else
    CANONICAL_PLUGINS=(
        "storage:supabase/plugins/storage/install.sql:Media Storage Assets (schema: media)"
        "subscriptions:supabase/plugins/subscriptions/install.sql:Subscriptions & Quota (schema: billing)"
        "webhooks:supabase/plugins/webhooks/install.sql:Asynchronous Outbox & Webhooks (schema: events)"
        "runners:supabase/plugins/runners/install.sql:Runners & Compute Fleet (schema: runners)"
        "automa:supabase/plugins/automa/install.sql:Automa Cloud Bridge (schema: automa)"
    )
fi

for item in "${CANONICAL_PLUGINS[@]}"; do
    IFS=":" read -r plugin_id sql_file desc <<< "$item"

    if [[ "$PLUGIN" != "all" && "$PLUGIN" != "$plugin_id" ]]; then
        continue
    fi

    if [[ ! -f "$sql_file" ]]; then
        echo "[-] Error: Plugin $ACTION file not found: $sql_file" >&2
        exit 1
    fi

    echo ""
    echo "--> ${ACTION^}ing Plugin: [$plugin_id] - $desc"
    if [[ "$TARGET" == "local" ]]; then
        DB_CONTAINER=$(docker ps --filter "name=supabase_db" --format "{{.Names}}" | head -n 1)
        if [[ -n "$DB_CONTAINER" ]]; then
            docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$sql_file"
        else
            supabase db query "--$TARGET" -f "$sql_file"
        fi
    else
        supabase db query "--$TARGET" -f "$sql_file"
    fi
    echo "    [OK] Successfully applied $sql_file"

    if [[ "$ACTION" == "install" && ("$plugin_id" == "automa" || "$plugin_id" == "runners") && "$WITH_SEED" == "true" ]]; then
        seed_file="supabase/plugins/$plugin_id/seed.sql"
        if [[ -f "$seed_file" ]]; then
            echo "    --> Applying sample data: $seed_file"
            if [[ "$TARGET" == "local" && -n "${DB_CONTAINER:-}" ]]; then
                docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$seed_file"
            else
                supabase db query "--$TARGET" -f "$seed_file"
            fi
            echo "    [OK] Sample data applied for $plugin_id"
        fi
    fi
done

echo ""
echo "===================================================================="
echo " [SUCCESS] All targeted plugins have been processed ($ACTION) successfully."
echo "===================================================================="
