# ============================================================================
# TUQUET-CLOUD ENVIRONMENT SWITCHER UTILITY (POWERSHELL / WINDOWS)
# Description: Switches the active target environment between local Docker,
#              Cloud Dev (dswhacsoaxgpfnkaxnhz), and Cloud Prod.
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('local', 'dev', 'prod')]
    [string]$Env = 'dev',

    [string]$ProjectRef = '',
    [string]$AnonKey = ''
)

$ErrorActionPreference = 'Stop'

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " [TUQUET-CLOUD] Environment Switcher (Target: $Env)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

switch ($Env) {
    'dev' {
        $devRef = "dswhacsoaxgpfnkaxnhz"
        Write-Host "Linking to Supabase Cloud Dev: [$devRef]..." -ForegroundColor Yellow
        $prevHttp = $env:HTTP_PROXY
        $prevHttps = $env:HTTPS_PROXY
        $env:HTTP_PROXY = "http://127.0.0.1:8118"
        $env:HTTPS_PROXY = "http://127.0.0.1:8118"

        & supabase link --project-ref $devRef 2>&1 | Out-Host

        $env:HTTP_PROXY = $prevHttp
        $env:HTTPS_PROXY = $prevHttps
        Write-Host "`n[SUCCESS] Active target is now Supabase Cloud Dev (dswhacsoaxgpfnkaxnhz)." -ForegroundColor Green
        Write-Host "API Endpoint: https://dswhacsoaxgpfnkaxnhz.supabase.co" -ForegroundColor Gray
    }
    'local' {
        Write-Host "Targeting Local Docker Supabase (127.0.0.1:54321)..." -ForegroundColor Yellow
        Write-Host "[SUCCESS] Active target is now Local Docker Supabase." -ForegroundColor Green
        Write-Host "API Endpoint: http://127.0.0.1:54321" -ForegroundColor Gray
        Write-Host "Studio:       http://localhost:54323" -ForegroundColor Gray
    }
    'prod' {
        if (-not $ProjectRef) {
            Write-Host "[INFO] Production project reference has not been specified yet." -ForegroundColor DarkYellow
            Write-Host "Usage: .\scripts\switch_env.ps1 -Env prod -ProjectRef <your-prod-ref>" -ForegroundColor Cyan
            exit 1
        }
        Write-Host "Linking to Supabase Cloud Production: [$ProjectRef]..." -ForegroundColor Yellow
        $prevHttp = $env:HTTP_PROXY
        $prevHttps = $env:HTTPS_PROXY
        $env:HTTP_PROXY = "http://127.0.0.1:8118"
        $env:HTTPS_PROXY = "http://127.0.0.1:8118"

        & supabase link --project-ref $ProjectRef 2>&1 | Out-Host

        $env:HTTP_PROXY = $prevHttp
        $env:HTTPS_PROXY = $prevHttps
        Write-Host "`n[SUCCESS] Active target is now Supabase Cloud Production ($ProjectRef)." -ForegroundColor Green
    }
}
Write-Host "====================================================================" -ForegroundColor Cyan
