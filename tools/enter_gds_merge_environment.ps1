$installRoot = Join-Path $env:LOCALAPPDATA "STOB_EDA\gds-merge"
$python = Join-Path $installRoot "venv\Scripts\python.exe"
$klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Run tools\setup_gds_merge_environment.ps1 first." }
$env:STOB_GDS_MERGE_HOME = $installRoot
$env:STOB_GDS_MERGE_PYTHON = $python
$env:STOB_KLAYOUT_EXE = $klayout
$env:STOB_OPENROAD_WSL = "/home/chandler/.local/stob-eda/openroad/bin/openroad"
$env:Path = (Join-Path $installRoot "venv\Scripts") + ";" + $env:Path
Write-Host "GDS merge environment active"
Write-Host "  Python : $python"
Write-Host "  KLayout: $klayout"
Write-Host "  OpenROAD (WSL): $env:STOB_OPENROAD_WSL"
