@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open_output_gds_3d.ps1" -MacroPath "design\hbm2_logic_3d.py" -ViewName "HBM2 package and routed logic die"
endlocal
