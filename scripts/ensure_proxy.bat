@echo off
rem Batch wrapper for ensure_proxy.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure_proxy.ps1" %*
