param([string]$Config="hardware_cost/config.json",[string]$Output="output/hbm2_hardware_cost")
$ErrorActionPreference="Stop"; $root=Split-Path -Parent $PSScriptRoot; $python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv. Install requirements.txt first." }
& $python tools/run_hbm2_hardware_cost.py --config $Config --output $Output; if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $python tools/validate_hbm2_hardware_cost.py --output $Output
exit $LASTEXITCODE
