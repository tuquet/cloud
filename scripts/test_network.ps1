# Diagnostic test for ports 2222 and 1080
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        if ($c.ConnectAsync("127.0.0.1", $p).Wait(500)) { $c.Close(); return $true }
        return $false
    } catch { return $false }
}

$p2222 = Test-Port 2222
$p1080 = Test-Port 1080

Write-Host "Cloudflare Bridge (2222): $(if ($p2222) {'ONLINE'} else {'OFFLINE'})" -ForegroundColor $(if ($p2222) {'Green'} else {'Red'})
Write-Host "SSH SOCKS5 Proxy  (1080): $(if ($p1080) {'ONLINE'} else {'OFFLINE'})" -ForegroundColor $(if ($p1080) {'Green'} else {'Red'})
