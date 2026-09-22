# ==============================================================================
# Script: stop_proxy.ps1
# Purpose: Stop background Cloudflare Bridge and SSH SOCKS5 Proxy daemons
# Encoding: Strict ASCII
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  STOPPING BACKGROUND TUNNEL & PROXY DAEMONS" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# Find and kill processes listening on port 2222 or 1080
$ports = @(2222, 1080)
foreach ($port in $ports) {
    Write-Host "[*] Checking listeners on port $port ..." -NoNewline
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($connections) {
        foreach ($conn in $connections) {
            $processId = $conn.OwningProcess
            $procName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
            Write-Host " Found PID $processId ($procName). Stopping..." -ForegroundColor Yellow
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
        Write-Host "     [+] Port $port is now released." -ForegroundColor Green
    } else {
        Write-Host " [NO ACTIVE LISTENER]" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "[SUCCESS] All proxy daemons have been stopped." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
