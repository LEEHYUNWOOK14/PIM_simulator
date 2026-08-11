@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\flow\run_flow.ps1"
endlocal

