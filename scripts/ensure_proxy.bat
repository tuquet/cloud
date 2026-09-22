@echo off
rem ================================================================
rem ENSURE PROXY (1-CLICK CHECK & LAUNCH)
rem Checks Port 2222 and Port 1080. If not running, starts them.
rem ================================================================
title Ensure Cloudflare & SOCKS5 Proxy
cls

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure_proxy.ps1"

pause
