@echo off
setlocal
cd /d "%~dp0"
title K90 Max ROOT init_boot Installer
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0K90_ROOT_INSTALLER.ps1" %*
set "K90_RC=%ERRORLEVEL%"
echo.
pause
exit /b %K90_RC%
