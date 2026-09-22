# ==============================================================================
# Script: run_with_proxy.ps1
# Purpose: Universal runner that ensures proxies are running, sets proxy env,
#          and executes the provided command seamlessly.
# Example: .\scripts\run_with_proxy.ps1 git push
#          .\scripts\run_with_proxy.ps1 supabase db push
# Encoding: Strict ASCII
# ==============================================================================

param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$CommandToRun
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. Run ensure_proxy to guarantee ports 2222 and 1080 are listening
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir\ensure_proxy.ps1"

# 2. Export environment variables
$env:ALL_PROXY   = "socks5://127.0.0.1:1080"
$env:HTTPS_PROXY = "socks5://127.0.0.1:1080"
$env:HTTP_PROXY  = "socks5://127.0.0.1:1080"

# 3. Execute the passed command
Write-Host ""
Write-Host "[RUNNING] $($CommandToRun -join ' ')" -ForegroundColor Yellow
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

& $CommandToRun[0] $CommandToRun[1..($CommandToRun.Length - 1)]

Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
Write-Host "[FINISHED] Execution completed." -ForegroundColor Cyan
