# ==============================================================================
# Script: ensure_proxy.ps1 (KISS & YAGNI)
# Purpose: Ensures Proxy (2222 & 1080) is online, sets proxy env, and optionally
#          executes any passed command.
# Usage:   .\scripts\ensure_proxy.ps1
#          .\scripts\ensure_proxy.ps1 git push
#          .\scripts\ensure_proxy.ps1 supabase db push
# Encoding: Strict ASCII
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Test-PortOpen([string]$ip, [int]$port) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($ip, $port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne(400, $false)) {
            $tcpClient.Close()
            return $false
        }
        $tcpClient.EndConnect($asyncResult)
        $tcpClient.Close()
        return $true
    } catch {
        return $false
    }
}

# 1. Ensure Cloudflare Bridge (Port 2222)
if (-not (Test-PortOpen "127.0.0.1" 2222)) {
    Write-Host "[*] Starting Cloudflare Bridge (2222)..." -ForegroundColor Yellow
    Start-Process "cloudflared" -ArgumentList "access tcp --hostname cdn.flowup.io.vn --url 127.0.0.1:2222" -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# 2. Ensure SSH SOCKS5 Proxy (Port 1080)
if (-not (Test-PortOpen "127.0.0.1" 1080)) {
    Write-Host "[*] Starting SSH SOCKS5 Proxy (1080)..." -ForegroundColor Yellow
    Start-Process "ssh" -ArgumentList "-N -D 1080 127.0.0.1" -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# 3. Export Proxy Environment Variables (Both Upper and Lowercase for Go CLI compatibility)
$proxyUrl = "socks5://127.0.0.1:1080"
$env:ALL_PROXY   = $proxyUrl
$env:all_proxy   = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:https_proxy = $proxyUrl
$env:HTTP_PROXY  = $proxyUrl
$env:http_proxy  = $proxyUrl

# 4. If command arguments were passed, execute them
if ($args.Count -gt 0) {
    & $args[0] $args[1..($args.Count - 1)]
} else {
    Write-Host "[OK] Proxy environment is ready ($proxyUrl)." -ForegroundColor Green
}
