param(
  [string]$Output="output/hardware_cost_adapter_v2",
  [string]$Report="reports/hardware_cost_adapter_v2"
)
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing project .venv." }
Push-Location $root
try {
  & $python tools/run_hardware_cost_adapter_v2.py --output $Output --report $Report
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python -m unittest verification.hardware_cost_regression.test_hardware_cost_adapter_v2 verification.hardware_cost_regression.test_hardware_cost_regression -v
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/validate_hardware_cost_regression.py --revisions "$Output/revisions" --baseline synthetic_low_area --output $Report
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/validate_hardware_cost_adapter_v2.py --output $Output --report $Report
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  Write-Host "HARDWARE_COST_ADAPTER_V2_REGRESSION PASS output=$Output report=$Report"
} finally {
  Pop-Location
}
