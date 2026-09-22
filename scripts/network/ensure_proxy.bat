@echo off
rem Batch wrapper for scripts/network/ensure_proxy.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure_proxy.ps1" %*
