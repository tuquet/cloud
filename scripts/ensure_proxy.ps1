# ==============================================================================
# Script: ensure_proxy.ps1
# Purpose: Self-healing proxy manager. Automatically detects if Cloudflare Bridge
#          (Port 2222) and SSH SOCKS5 Proxy (Port 1080) are running. If not, starts
#          them in the background automatically without depending on external VBS.
# Encoding: Strict ASCII
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Test-PortOpen([string]$ip, [int]$port) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($ip, $port, $null, $null)
        $waitSuccess = $asyncResult.AsyncWaitHandle.WaitOne(400, $false)
        if (-not $waitSuccess) {
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

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  SELF-HEALING PROXY CHECK (ZERO DEPENDENCY)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# STEP 1: Verify & Start Cloudflare Tunnel Bridge (Port 2222)
# ------------------------------------------------------------------------------
Write-Host "[1/2] Checking Cloudflare Bridge on 127.0.0.1:2222 ..." -NoNewline

$bridgeActive = Test-PortOpen "127.0.0.1" 2222
if ($bridgeActive) {
    Write-Host " [ALREADY RUNNING]" -ForegroundColor Green
} else {
    Write-Host " [NOT RUNNING]" -ForegroundColor Yellow
    Write-Host "      Starting cloudflared tunnel in background..." -ForegroundColor White

    Start-Process -FilePath "cloudflared" `
        -ArgumentList "access tcp --hostname cdn.flowup.io.vn --url 127.0.0.1:2222" `
        -WindowStyle Hidden

    # Wait up to 6 seconds for bridge to listen
    $attempts = 0
    while ($attempts -lt 12) {
        Start-Sleep -Milliseconds 500
        $bridgeActive = Test-PortOpen "127.0.0.1" 2222
        if ($bridgeActive) { break }
        $attempts++
    }

    if ($bridgeActive) {
        Write-Host "      [+] Cloudflare Bridge is now online!" -ForegroundColor Green
    } else {
        Write-Host "      [!] Failed to start Cloudflare Bridge. Check if cloudflared is installed." -ForegroundColor Red
    }
}

# ------------------------------------------------------------------------------
# STEP 2: Verify & Start SSH SOCKS5 Proxy (Port 1080)
# ------------------------------------------------------------------------------
Write-Host "[2/2] Checking SSH SOCKS5 Proxy on 127.0.0.1:1080 ..." -NoNewline

$proxyActive = Test-PortOpen "127.0.0.1" 1080
if ($proxyActive) {
    Write-Host " [ALREADY RUNNING]" -ForegroundColor Green
} else {
    Write-Host " [NOT RUNNING]" -ForegroundColor Yellow

    if (-not $bridgeActive) {
        Write-Host "      [!] Cannot start SOCKS5 proxy because Cloudflare Bridge (2222) is down." -ForegroundColor Red
    } else {
        Write-Host "      Starting SSH SOCKS5 daemon in background..." -ForegroundColor White

        Start-Process -FilePath "ssh" `
            -ArgumentList "-N -D 1080 127.0.0.1" `
            -WindowStyle Hidden

        # Wait up to 6 seconds for SOCKS5 proxy to listen
        $attempts = 0
        while ($attempts -lt 12) {
            Start-Sleep -Milliseconds 500
            $proxyActive = Test-PortOpen "127.0.0.1" 1080
            if ($proxyActive) { break }
            $attempts++
        }

        if ($proxyActive) {
            Write-Host "      [+] SSH SOCKS5 Proxy is now online on port 1080!" -ForegroundColor Green
        } else {
            Write-Host "      [!] Failed to start SOCKS5 proxy. Check SSH key and credentials." -ForegroundColor Red
        }
    }
}

# ------------------------------------------------------------------------------
# STEP 3: Configure Environment Variables
# ------------------------------------------------------------------------------
if ($proxyActive) {
    $env:ALL_PROXY   = "socks5://127.0.0.1:1080"
    $env:HTTPS_PROXY = "socks5://127.0.0.1:1080"
    $env:HTTP_PROXY  = "socks5://127.0.0.1:1080"

    Write-Host ""
    Write-Host "[SUCCESS] All proxy tunnels are active and healthy!" -ForegroundColor Green
    Write-Host "          Environment variable `$env:ALL_PROXY set to socks5://127.0.0.1:1080" -ForegroundColor Cyan
    Write-Host "          You can now execute 'git push' or 'supabase db push' safely." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "[WARNING] Proxy environment could not be fully initialized." -ForegroundColor Red
}

Write-Host "=================================================================" -ForegroundColor Cyan
