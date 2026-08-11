@echo off
setlocal
set "VIEW=%~1"
if "%VIEW%"=="" set "VIEW=gds"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open_hbm2_architecture.ps1" -View "%VIEW%"
exit /b %ERRORLEVEL%

