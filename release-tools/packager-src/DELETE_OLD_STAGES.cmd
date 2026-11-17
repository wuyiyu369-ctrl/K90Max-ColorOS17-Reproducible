@echo off
setlocal
cd /d "%~dp0"
title K90 Max Old Stage Cleanup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup_old_stages.ps1"
set "K90_RC=%ERRORLEVEL%"
echo.
pause
exit /b %K90_RC%
