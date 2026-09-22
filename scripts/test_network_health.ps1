# ==============================================================================
# Script: test_network_health.ps1
# Purpose: Diagnostics for Cloudflare Bridge (2222) and SOCKS5 Proxy (1080)
# Encoding: Strict ASCII
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTIC TEST: NETWORK PROXY HEALTH CHECK" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Test Port 2222 (Cloudflare Tunnel Bridge)
Write-Host "[1/2] Checking Cloudflare Bridge on 127.0.0.1:2222 ..." -NoNewline
$bridgeConn = Test-NetConnection -ComputerName 127.0.0.1 -Port 2222 -WarningAction SilentlyContinue
if ($bridgeConn.TcpTestSucceeded) {
    Write-Host " [ONLINE]" -ForegroundColor Green
} else {
    Write-Host " [OFFLINE]" -ForegroundColor Red
    Write-Host "      Please ensure cloudflare_ssh_bridge.bat is running via VBS or CMD." -ForegroundColor Yellow
}

# 2. Test Port 1080 (SSH SOCKS5 Proxy)
Write-Host "[2/2] Checking SSH SOCKS5 Proxy on 127.0.0.1:1080 ..." -NoNewline
$proxyConn = Test-NetConnection -ComputerName 127.0.0.1 -Port 1080 -WarningAction SilentlyContinue
if ($proxyConn.TcpTestSucceeded) {
    Write-Host " [ONLINE]" -ForegroundColor Green
} else {
    Write-Host " [OFFLINE]" -ForegroundColor Red
    Write-Host "      Please launch scripts/start_socks5_proxy.bat or run: ssh -N -D 1080 127.0.0.1" -ForegroundColor Yellow
}

Write-Host ""
if ($bridgeConn.TcpTestSucceeded -and $proxyConn.TcpTestSucceeded) {
    Write-Host "[SUCCESS] All proxy tunnels are healthy and ready for Git and Supabase CLI!" -ForegroundColor Green
} else {
    Write-Host "[WARN] One or more tunnel services are down. Please check above instructions." -ForegroundColor Yellow
}
Write-Host "=================================================================" -ForegroundColor Cyan
