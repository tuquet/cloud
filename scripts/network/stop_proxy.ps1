# Script to stop background proxy daemons
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Stopping background proxy daemons..." -ForegroundColor Yellow
$ports = @(2222, 1080)
foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($connections) {
        foreach ($conn in $connections) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        }
        Write-Host "[+] Port $port is released." -ForegroundColor Green
    }
}
Write-Host "[OK] Proxy daemons stopped." -ForegroundColor Green
