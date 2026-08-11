@echo off
setlocal
set "GDS=%~1"
if "%GDS%"=="" set "GDS=output\output.gds"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open_klayout.ps1" -GdsPath "%GDS%"
endlocal
