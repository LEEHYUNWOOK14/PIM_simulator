param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "STOB_EDA\gds-merge"),
    [string]$Python311 = "C:\Users\Admin\AppData\Local\Programs\Python\Python311\python.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$venv = Join-Path $InstallRoot "venv"
$python = Join-Path $venv "Scripts\python.exe"
$klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
if (-not (Test-Path -LiteralPath $Python311)) { throw "Python 3.11 not found: $Python311" }
if (-not (Test-Path -LiteralPath $klayout)) { throw "KLayout GUI not found: $klayout" }
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
if (-not (Test-Path -LiteralPath $python)) {
    & $Python311 -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
}
& $python -m pip install --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) { throw "pip bootstrap failed" }
& $python -m pip install -r (Join-Path $PSScriptRoot "gds_merge_requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "GDS merge package installation failed" }

[Environment]::SetEnvironmentVariable("STOB_GDS_MERGE_HOME", $InstallRoot, "User")
[Environment]::SetEnvironmentVariable("STOB_GDS_MERGE_PYTHON", $python, "User")
[Environment]::SetEnvironmentVariable("STOB_KLAYOUT_EXE", $klayout, "User")
[Environment]::SetEnvironmentVariable("STOB_OPENROAD_WSL", "/home/chandler/.local/stob-eda/openroad/bin/openroad", "User")
$env:STOB_GDS_MERGE_HOME = $InstallRoot
$env:STOB_GDS_MERGE_PYTHON = $python
$env:STOB_KLAYOUT_EXE = $klayout
$env:STOB_OPENROAD_WSL = "/home/chandler/.local/stob-eda/openroad/bin/openroad"

& $python (Join-Path $PSScriptRoot "check_gds_merge_environment.py") `
    --output (Join-Path $InstallRoot "smoke") `
    --report (Join-Path $repoRoot "reports\floorplan_optimization\results\gds_merge_environment_smoke.json")
if ($LASTEXITCODE -ne 0) { throw "GDS merge smoke test failed" }
Write-Host "GDS_MERGE_ENVIRONMENT PASS home=$InstallRoot python=$python"
