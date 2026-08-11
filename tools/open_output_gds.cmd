@echo off
setlocal
set "ROOT=%~dp0.."
set "GDS=%ROOT%\output\output.gds"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_output_gds.ps1" -GdsPath "%GDS%"
if errorlevel 1 (
  echo.
  echo Put the OpenROAD result at:
  echo   %GDS%
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\open_klayout.ps1" -GdsPath "%GDS%"
endlocal

