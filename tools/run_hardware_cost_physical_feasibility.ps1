param(
  [string]$EvidenceDir="reports/groot_normalization/physical_feasibility",
  [string]$Output="reports/hardware_cost_physical_feasibility/physical_feasibility.json",
  [string]$Report="reports/hardware_cost_physical_feasibility/physical_feasibility_report.md",
  [string]$Manifest="hardware_cost/regression/physical_feasibility_manifest_2026_08_12.json",
  [string]$Revision="hardware_cost/regression/revisions/physical_feasibility_2026_08_12.json",
  [string]$BaselineManifest="hardware_cost/regression/baseline_manifest.json",
  [string]$BaselineRevision="hardware_cost/regression/revisions/provisional_baseline_2026_08_11.json",
  [string]$Baseline="provisional_baseline_2026_08_11",
  [string]$RegressionReport="reports/hardware_cost_regression",
  [switch]$RunPhysicalFlow
)
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv. Install requirements.txt first." }
Push-Location $root
try {
  if ($RunPhysicalFlow) {
    & wsl -e bash tools/run_hardware_cost_integrated_placement.sh
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & wsl -e bash tools/run_hardware_cost_integrated_sta.sh
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & wsl -e bash tools/run_hardware_cost_integrated_coarse_route.sh
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
  }
  & $python tools/collect_physical_feasibility_evidence.py --evidence-dir $EvidenceDir --output $Output --report $Report
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/validate_physical_feasibility.py --input $Output
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/capture_hardware_cost_revision.py --manifest $BaselineManifest --output $BaselineRevision
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/capture_hardware_cost_revision.py --manifest $Manifest --output $Revision
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/compare_hardware_cost_revisions.py --revisions hardware_cost/regression/revisions --baseline $Baseline --output $RegressionReport
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python -m unittest verification.hardware_cost_regression.test_physical_feasibility_gate -v
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  $gate = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
  Write-Host "HARDWARE_COST_PHYSICAL_FEASIBILITY PIPELINE_PASS gate_status=$($gate.status) freeze=$($gate.rtl_freeze_allowed) output=$Output report=$Report"
} finally { Pop-Location }
