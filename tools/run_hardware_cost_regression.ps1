param(
  [string]$Manifest="hardware_cost/regression/baseline_manifest.json",
  [string]$Baseline="provisional_baseline_2026_08_11",
  [string]$Revisions="hardware_cost/regression/revisions",
  [string]$Output="reports/hardware_cost_regression"
)
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv. Install requirements.txt first." }
Push-Location $root
try {
  $manifestData=Get-Content -Raw -Encoding UTF8 $Manifest | ConvertFrom-Json
  $revisionId=$manifestData.revision_id
  $snapshot=Join-Path $Revisions ($revisionId+".json")
  & $python tools/capture_hardware_cost_revision.py --manifest $Manifest --output $snapshot
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/compare_hardware_cost_revisions.py --revisions $Revisions --baseline $Baseline --output $Output
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python -m unittest verification.hardware_cost_regression.test_hardware_cost_regression -v
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/validate_hardware_cost_regression.py --revisions $Revisions --baseline $Baseline --output $Output
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  Write-Host "HARDWARE_COST_REGRESSION PASS baseline=$Baseline output=$Output"
} finally { Pop-Location }
