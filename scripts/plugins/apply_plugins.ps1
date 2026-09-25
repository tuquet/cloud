# ============================================================================
# TUQUET-CLOUD PLUGIN RUNNER UTILITY
# Description: Automates the atomic installation of plugins in the canonical
#              architectural order against local or linked Supabase databases.
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('local', 'linked')]
    [string]$Target = 'local',

    [ValidateSet('all', 'storage', 'subscriptions', 'webhooks', 'automa')]
    [string]$Plugin = 'all',

    [switch]$WithSeed = $true
)

$ErrorActionPreference = 'Stop'

# Define canonical installation order (Infrastructure -> Billing -> Events -> Business Domain)
$CanonicalOrder = @(
    @{ Id = 'storage';       Path = 'supabase/plugins/storage/install.sql';       Desc = 'Media Storage Assets (schema: media)' },
    @{ Id = 'subscriptions'; Path = 'supabase/plugins/subscriptions/install.sql'; Desc = 'Subscriptions & Quota (schema: billing)' },
    @{ Id = 'webhooks';      Path = 'supabase/plugins/webhooks/install.sql';      Desc = 'Asynchronous Outbox & Webhooks (schema: events)' },
    @{ Id = 'automa';        Path = 'supabase/plugins/automa/install.sql';        Desc = 'Automa Cloud Bridge (schema: automa)' }
)

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Plugin Pipeline Runner (Target: $Target)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

$TargetPlugins = if ($Plugin -eq 'all') {
    $CanonicalOrder
} else {
    $CanonicalOrder | Where-Object { $_.Id -eq $Plugin }
}

foreach ($item in $TargetPlugins) {
    $pluginId = $item.Id
    $installFile = $item.Path
    $desc = $item.Desc

    if (-not (Test-Path $installFile)) {
        Write-Error "Plugin install file not found: $installFile"
        continue
    }

    Write-Host "`n--> Installing Plugin: [$pluginId] - $desc" -ForegroundColor Yellow

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    if ($Target -eq 'local') {
        Get-Content $installFile -Raw | docker exec -i supabase_db_tuquet-cloud psql -U postgres -d postgres 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    } else {
        $cmdArgs = @('db', 'query', "--$Target", '-f', $installFile)
        & supabase @cmdArgs 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    }
    
    $ErrorActionPreference = $prevEAP

    if ($exitCode -ne 0) {
        Write-Error "Failed to install plugin [$pluginId] (Exit code: $exitCode)"
        exit $exitCode
    }

    Write-Host "    [OK] Successfully applied $installFile" -ForegroundColor Green

    # Apply seed data for automa if requested
    if ($pluginId -eq 'automa' -and $WithSeed) {
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
Write-Host " [SUCCESS] All targeted plugins have been installed successfully." -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
