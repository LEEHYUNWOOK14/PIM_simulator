@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate_hbm2_architecture.ps1" %*
exit /b %ERRORLEVEL%

