# ============================================================================
# TUQUET-CLOUD DATABASE RESET & PROVISIONING ORCHESTRATOR (POWERSHELL / WINDOWS)
# Description: Resets Supabase database (local Docker or linked Cloud project),
#              runs foundational migrations, applies canonical plugins in order,
#              and seeds Model 1 standard QA test data.
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('local', 'linked', 'dev')]
    [string]$Target = 'local',

    [string]$ProjectRef = 'dswhacsoaxgpfnkaxnhz',

    [switch]$WithPlugins = $true,

    [switch]$WithSeed = $true,

    [switch]$WithTests = $false,

    [switch]$Force = $false
)

$ErrorActionPreference = 'Stop'

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Database Reset & Provisioning Orchestrator" -ForegroundColor Cyan
Write-Host " Target: $Target" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 1. Safety verification for remote cloud targets
if ($Target -ne 'local') {
    Write-Host "`n[DANGER] WARNING: You are targeting a REMOTE Supabase database ($ProjectRef)!" -ForegroundColor Red
    Write-Host "This operation will completely DROP all data, schemas, and tables on Supabase Cloud." -ForegroundColor Red

    if (-not $Force) {
        $confirmation = Read-Host "`nAre you sure you want to completely RESET the remote database? (Type 'RESET' to confirm)"
        if ($confirmation -ne 'RESET') {
            Write-Host "[ABORTED] Reset cancelled by user. No changes were made." -ForegroundColor Yellow
            exit 0
        }
    }

    # Ensure Bridge HTTP Forwarder proxy is active
    if (-not $env:HTTP_PROXY) {
        $env:HTTP_PROXY = "http://127.0.0.1:8118"
        $env:HTTPS_PROXY = "http://127.0.0.1:8118"
    }
    Write-Host "Routing traffic via Bridge HTTP Forwarder ($env:HTTP_PROXY)..." -ForegroundColor Gray
}

# 2. Step 1: Execute Database Reset
Write-Host "`n--> Step 1/4: Resetting database schema and migrations..." -ForegroundColor Yellow

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

if ($Target -eq 'local') {
    & supabase db reset --local --no-seed 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE
} else {
    $targetFlag = if ($Target -eq 'dev') { 'linked' } else { $Target }
    & supabase db reset "--$targetFlag" --no-seed --yes 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE
}

$ErrorActionPreference = $prevEAP

if ($exitCode -ne 0) {
    Write-Error "Database reset failed with exit code: $exitCode"
    exit $exitCode
}
Write-Host "    [OK] Database core migrations applied successfully." -ForegroundColor Green

# 3. Step 2: Apply Plugins in Canonical Order
if ($WithPlugins) {
    Write-Host "`n--> Step 2/4: Applying canonical plugins (storage, subscriptions, webhooks, runners, automation)..." -ForegroundColor Yellow
    $pluginScript = "scripts/plugins/apply_plugins.ps1"
    if (Test-Path $pluginScript) {
        & powershell -ExecutionPolicy Bypass -File $pluginScript -Target $Target -Plugin all -Action install 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install plugins on target $Target."
            exit $LASTEXITCODE
        }
    } else {
        Write-Warning "Plugin runner not found at $pluginScript. Skipping plugin installation."
    }
} else {
    Write-Host "`n--> Step 2/4: Skipping plugins as requested (-WithPlugins:$false)." -ForegroundColor DarkGray
}

# 4. Step 3: Apply Model 1 Dev Test Seed Data
if ($WithSeed) {
    Write-Host "`n--> Step 3/4: Seeding Model 1 development and QA test data..." -ForegroundColor Yellow
    $seedFile = "supabase/seed.sql"
    if (Test-Path $seedFile) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'

        if ($Target -eq 'local') {
            Get-Content $seedFile -Raw | docker exec -i supabase_db_cloud psql -U postgres -d postgres 2>&1 | Out-Host
            $exitCode = $LASTEXITCODE
        } else {
            $targetFlag = if ($Target -eq 'dev') { 'linked' } else { $Target }
            & supabase db query "--$targetFlag" -f $seedFile 2>&1 | Out-Host
            $exitCode = $LASTEXITCODE
        }

        $ErrorActionPreference = $prevEAP

        if ($exitCode -ne 0) {
            Write-Error "Failed to apply seed data ($seedFile). Exit code: $exitCode"
            exit $exitCode
        }
        Write-Host "    [OK] Model 1 seed data applied successfully." -ForegroundColor Green
    } else {
        Write-Warning "Seed file not found at $seedFile."
    }
} else {
    Write-Host "`n--> Step 3/4: Skipping seed data as requested (-WithSeed:$false)." -ForegroundColor DarkGray
}

# 5. Step 4: Run Verification Tests (Optional)
if ($WithTests) {
    Write-Host "`n--> Step 4/4: Executing database verification test suite..." -ForegroundColor Yellow
    $testScript = "scripts/test_db.ps1"
    if (Test-Path $testScript) {
        & powershell -ExecutionPolicy Bypass -File $testScript -Target $Target 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Database verification tests failed on target $Target."
            exit $LASTEXITCODE
        }
    }
} else {
    Write-Host "`n--> Step 4/4: Skipping test verification (run with -WithTests to verify)." -ForegroundColor DarkGray
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] Database reset and initialization complete for target: $Target" -ForegroundColor Green
Write-Host " Universal Test Password: Tuquet1102@" -ForegroundColor White
if ($Target -eq 'local') {
    Write-Host " API URL:   http://127.0.0.1:55321" -ForegroundColor Gray
    Write-Host " Studio:    http://localhost:55323" -ForegroundColor Gray
} else {
    Write-Host " API URL:   https://$ProjectRef.supabase.co" -ForegroundColor Gray
}
Write-Host "====================================================================" -ForegroundColor Cyan
