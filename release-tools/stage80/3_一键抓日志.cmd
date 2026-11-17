@echo off
setlocal
cd /d "%~dp0"
title K90 Max Complete Log Collector
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0K90_LOG_COLLECTOR.ps1"
set "K90_RC=%ERRORLEVEL%"
echo.
pause
exit /b %K90_RC%
