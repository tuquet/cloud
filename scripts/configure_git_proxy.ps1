# ==============================================================================
# Script: configure_git_proxy.ps1
# Purpose: Configure local Git repository to route pushes through SOCKS5 proxy
# Target Proxy: socks5://127.0.0.1:1080
# Encoding: Strict ASCII
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  CONFIGURING LOCAL GIT REPOSITORY PROXY (127.0.0.1:1080)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verify if we are inside a Git repository
$gitStatus = git rev-parse --is-inside-work-tree 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Not a git repository. Initializing local git repository..." -ForegroundColor Yellow
    git init
}

# 2. Configure HTTP and HTTPS proxy for local repository
Write-Host "[+] Configuring local http.proxy and https.proxy..." -ForegroundColor Green
git config --local http.proxy "socks5://127.0.0.1:1080"
git config --local https.proxy "socks5://127.0.0.1:1080"

# 3. Configure SSH command to route through connect.exe if using SSH remote
Write-Host "[+] Configuring local core.sshCommand for SSH remotes..." -ForegroundColor Green
git config --local core.sshCommand "ssh -o 'ProxyCommand=connect -S 127.0.0.1:1080 %h %p'"

# 4. Display current settings
Write-Host ""
Write-Host "[OK] Current local Git proxy settings:" -ForegroundColor Cyan
Write-Host "http.proxy     : $(git config --local --get http.proxy)" -ForegroundColor White
Write-Host "https.proxy    : $(git config --local --get https.proxy)" -ForegroundColor White
Write-Host "core.sshCommand: $(git config --local --get core.sshCommand)" -ForegroundColor White
Write-Host ""
Write-Host "[INFO] Configuration complete! All 'git push' commands in this repo" -ForegroundColor Green
Write-Host "       will now route through SOCKS5 proxy at 127.0.0.1:1080." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
