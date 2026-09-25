# ============================================================================
# TUQUET-CLOUD PLUGIN RUNNER UTILITY
# Description: Automates the atomic installation and uninstallation of plugins
#              in canonical architectural order against local or linked Supabase.
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('local', 'linked')]
    [string]$Target = 'local',

    [ValidateSet('all', 'storage', 'subscriptions', 'webhooks', 'automa')]
    [string]$Plugin = 'all',

    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install',

    [switch]$WithSeed = $true
)

$ErrorActionPreference = 'Stop'

# Define canonical installation order (Infrastructure -> Billing -> Events -> Business Domain)
$CanonicalOrder = @(
    @{ Id = 'storage';       Install = 'supabase/plugins/storage/install.sql';       Uninstall = 'supabase/plugins/storage/uninstall.sql';       Desc = 'Media Storage Assets (schema: media)' },
    @{ Id = 'subscriptions'; Install = 'supabase/plugins/subscriptions/install.sql'; Uninstall = 'supabase/plugins/subscriptions/uninstall.sql'; Desc = 'Subscriptions & Quota (schema: billing)' },
    @{ Id = 'webhooks';      Install = 'supabase/plugins/webhooks/install.sql';      Uninstall = 'supabase/plugins/webhooks/uninstall.sql';      Desc = 'Asynchronous Outbox & Webhooks (schema: events)' },
    @{ Id = 'automa';        Install = 'supabase/plugins/automa/install.sql';        Uninstall = 'supabase/plugins/automa/uninstall.sql';        Desc = 'Automa Cloud Bridge (schema: automa)' }
)

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Plugin Pipeline Runner (Action: $Action, Target: $Target)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

$TargetPlugins = if ($Plugin -eq 'all') {
    $CanonicalOrder
} else {
    $CanonicalOrder | Where-Object { $_.Id -eq $Plugin }
}

# Reverse execution order during uninstallation to respect dependency graph
if ($Action -eq 'uninstall') {
    [array]::Reverse($TargetPlugins)
}

foreach ($item in $TargetPlugins) {
    $pluginId = $item.Id
    $sqlFile = if ($Action -eq 'install') { $item.Install } else { $item.Uninstall }
    $desc = $item.Desc

    if (-not (Test-Path $sqlFile)) {
        Write-Error "Plugin $Action file not found: $sqlFile"
        continue
    }

    $actionVerb = if ($Action -eq 'install') { "Installing" } else { "Uninstalling" }
    Write-Host "`n--> $actionVerb Plugin: [$pluginId] - $desc" -ForegroundColor Yellow

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    if ($Target -eq 'local') {
        Get-Content $sqlFile -Raw | docker exec -i supabase_db_tuquet-cloud psql -U postgres -d postgres 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    } else {
        $cmdArgs = @('db', 'query', "--$Target", '-f', $sqlFile)
        & supabase @cmdArgs 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    }
    
    $ErrorActionPreference = $prevEAP

    if ($exitCode -ne 0) {
        Write-Error "Failed to $Action plugin [$pluginId] (Exit code: $exitCode)"
        exit $exitCode
    }

    Write-Host "    [OK] Successfully applied $sqlFile" -ForegroundColor Green

    # Apply seed data for automa if requested during install
    if ($Action -eq 'install' -and $pluginId -eq 'automa' -and $WithSeed) {
        $seedFile = 'supabase/plugins/automa/seed.sql'
        if (Test-Path $seedFile) {
            Write-Host "    --> Applying sample data: $seedFile" -ForegroundColor DarkYellow
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            if ($Target -eq 'local') {
                Get-Content $seedFile -Raw | docker exec -i supabase_db_tuquet-cloud psql -U postgres -d postgres 2>&1 | Out-Host
            } else {
                & supabase db query "--$Target" -f $seedFile 2>&1 | Out-Host
            }
            $ErrorActionPreference = $prevEAP
            Write-Host "    [OK] Sample data applied for automa" -ForegroundColor Green
        }
    }
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] All targeted plugins have been processed ($Action) successfully." -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
