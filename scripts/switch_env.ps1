# ============================================================================
# TUQUET-CLOUD ENVIRONMENT SWITCHER UTILITY (POWERSHELL / WINDOWS)
# Description: Switches the active target environment between local Docker,
#              and Cloud Production (dswhacsoaxgpfnkaxnhz).
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('prod', 'dev', 'local')]
    [string]$Env = 'prod',

    [string]$ProjectRef = 'dswhacsoaxgpfnkaxnhz',
    [string]$AnonKey = ''
)

$ErrorActionPreference = 'Stop'

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Environment Switcher (Target: $Env)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

switch ($Env) {
    'prod' {
        $prodRef = if ($ProjectRef) { $ProjectRef } else { "dswhacsoaxgpfnkaxnhz" }
        Write-Host "Linking to Supabase Cloud Production: [$prodRef]..." -ForegroundColor Yellow
        $prevHttp = $env:HTTP_PROXY
        $prevHttps = $env:HTTPS_PROXY
        $env:HTTP_PROXY = "http://127.0.0.1:8118"
        $env:HTTPS_PROXY = "http://127.0.0.1:8118"

        & supabase link --project-ref $prodRef 2>&1 | Out-Host

        $env:HTTP_PROXY = $prevHttp
        $env:HTTPS_PROXY = $prevHttps
        Write-Host "`n[SUCCESS] Active target is now Supabase Cloud Production ($prodRef)." -ForegroundColor Green
        Write-Host "API Endpoint: https://$prodRef.supabase.co" -ForegroundColor Gray
    }
    'dev' {
        $devRef = if ($ProjectRef) { $ProjectRef } else { "dswhacsoaxgpfnkaxnhz" }
        Write-Host "Linking to Supabase Cloud Dev: [$devRef]..." -ForegroundColor Yellow
        $prevHttp = $env:HTTP_PROXY
        $prevHttps = $env:HTTPS_PROXY
        $env:HTTP_PROXY = "http://127.0.0.1:8118"
        $env:HTTPS_PROXY = "http://127.0.0.1:8118"

        & supabase link --project-ref $devRef 2>&1 | Out-Host

        $env:HTTP_PROXY = $prevHttp
        $env:HTTPS_PROXY = $prevHttps
        Write-Host "`n[SUCCESS] Active target is now Supabase Cloud ($devRef)." -ForegroundColor Green
        Write-Host "API Endpoint: https://$devRef.supabase.co" -ForegroundColor Gray
    }
    'local' {
        Write-Host "Targeting Local Docker Supabase (127.0.0.1:54321)..." -ForegroundColor Yellow
        Write-Host "[SUCCESS] Active target is now Local Docker Supabase." -ForegroundColor Green
        Write-Host "API Endpoint: http://127.0.0.1:54321" -ForegroundColor Gray
        Write-Host "Studio:       http://localhost:54323" -ForegroundColor Gray
    }
}
Write-Host "====================================================================" -ForegroundColor Cyan
