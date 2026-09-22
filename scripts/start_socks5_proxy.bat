@echo off
rem ================================================================
rem SOCKS5 PROXY DAEMON OVER CLOUDFLARE SSH BRIDGE (PORT 1080)
rem Prerequisites: cloudflare_ssh_bridge.bat running on port 2222
rem ================================================================
title SSH SOCKS5 Proxy Bridge (Port 1080)
cls

echo ================================================================
echo   STARTING SSH SOCKS5 PROXY ON 127.0.0.1:1080
echo ================================================================
echo.
echo   Connecting to Cloudflare Bridge at 127.0.0.1:2222 ...
echo   Using ~/.ssh/config rules (User: root, Key: id_ed25519)
echo.
echo   Leave this window open while doing Git push or Supabase CLI work.
echo   Press Ctrl+C to stop the proxy.
echo ================================================================
echo.

ssh -N -D 1080 127.0.0.1

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] SSH tunnel terminated with error code %ERRORLEVEL%.
    echo Please verify cloudflare_ssh_bridge.bat is running on port 2222.
    pause
)
