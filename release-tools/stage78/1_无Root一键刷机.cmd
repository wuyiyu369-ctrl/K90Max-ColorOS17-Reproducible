@echo off
setlocal
cd /d "%~dp0"
title K90 Max ColorOS 17 Stage78 No Root Flash
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0K90_STAGE78_FLASH.ps1"
set "K90_RC=%ERRORLEVEL%"
echo.
if not "%K90_RC%"=="0" echo Flash stopped with error code %K90_RC%.
if exist "%~dp0DELETE_AFTER_FLASH.flag" exit /b %K90_RC%
pause
exit /b %K90_RC%
