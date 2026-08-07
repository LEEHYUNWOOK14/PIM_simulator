param(
  [ValidateSet("steady","transient")][string]$Analysis="steady",
  [string]$PowerTrace="",
  [string]$Profile="uniform",
  [string]$StackConfig="design/hbm2_architecture.json",
  [ValidateSet("reference")][string]$Solver="reference"
)
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot; $python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv; install requirements.txt." }
$a=@("tools/run_hbm2_thermal.py","--profile",$Profile)
if ($Analysis -eq "transient") { $a+="--transient" }
if ($PowerTrace) { $a+=@("--events",$PowerTrace) }
& $python @a; if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $python tools/validate_hbm2_thermal.py; if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $python tools/sweep_hbm2_thermal.py; if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $python tools/export_hbm2_hotspot.py
