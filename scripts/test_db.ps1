# ============================================================================
# TUQUET-CLOUD DATABASE TEST RUNNER (POWERSHELL / WINDOWS / CI)
# Description: Executes automated SQL verification suites against local Supabase
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('local', 'dev', 'linked')]
    [string]$Target = 'local'
)

$ErrorActionPreference = 'Stop'

# Configure Bridge HTTP Forwarder proxy for remote targets if not already set
if ($Target -ne 'local' -and (-not $env:HTTP_PROXY)) {
    $env:HTTP_PROXY = "http://127.0.0.1:8118"
    $env:HTTPS_PROXY = "http://127.0.0.1:8118"
}

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Database Test Suite Runner (Target: $Target)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

$TestFiles = @(
    "tests/db/01_verify_core_iam.sql",
    "tests/db/02_verify_automation_plugin.sql",
    "tests/db/03_verify_browsers_plugin.sql",
    "tests/db/03_verify_storage_plugin.sql",
    "tests/db/04_verify_subscriptions_plugin.sql",
    "tests/db/05_verify_webhooks_plugin.sql",
    "tests/db/06_verify_test_presets.sql"
)

# Ensure provision helper procedure is present for verification
$helperFile = "tests/presets/sql/00_provision_helper.sql"
if (Test-Path $helperFile) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    if ($Target -eq 'local') {
        Get-Content $helperFile -Raw | docker exec -i supabase_db_cloud psql -U postgres -d postgres 2>&1 | Out-Null
    } else {
        $targetFlag = if ($Target -eq 'dev') { 'linked' } else { $Target }
        & supabase db query "--$targetFlag" -f $helperFile 2>&1 | Out-Null
    }
    $ErrorActionPreference = $prevEAP
}

foreach ($testFile in $TestFiles) {
    if (-not (Test-Path $testFile)) {
        Write-Error "[-] Error: Test file not found: $testFile"
        exit 1
    }

    Write-Host "`n--> Running Test: $testFile" -ForegroundColor Yellow

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    if ($Target -eq 'local') {
        Get-Content $testFile -Raw | docker exec -i supabase_db_cloud psql -U postgres -d postgres 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    } else {
        $targetFlag = if ($Target -eq 'dev') { 'linked' } else { $Target }
        & supabase db query "--$targetFlag" -f $testFile 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    }

    $ErrorActionPreference = $prevEAP

    if ($exitCode -ne 0) {
        Write-Error "Test failed: $testFile (Exit code: $exitCode)"
        exit $exitCode
    }
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " [ALL TESTS PASSED] Database integrity verified 100% successfully." -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
