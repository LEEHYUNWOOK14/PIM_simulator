param(
  [string]$Manifest="verification/rtl_to_3d/fixtures/report_manifest.json",
  [string]$Output="output/rtl_to_3d",
  [string]$ThermalOutput="output/hbm2_thermal/rtl_mapped",
  [switch]$SkipHardwareCost
)
$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
$python=Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv. Install requirements.txt first." }
Push-Location $root
try {
  $normalized=Join-Path $Output "normalized_input.json"
  $mapped=Join-Path $Output "mapped_power.json"
  & $python tools/collect_rtl_physical_inputs.py --manifest $Manifest --output $normalized
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/rtl_to_3d_power_map.py --input $normalized --output $Output
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python tools/run_hbm2_thermal.py --mapped-power $mapped --output $ThermalOutput
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  & $python -m unittest verification.rtl_to_3d.test_rtl_to_3d -v
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  if (-not $SkipHardwareCost) {
    $thermalSummary=(Join-Path $ThermalOutput "summary.json").Replace("\","/")
    & $python tools/run_hbm2_hardware_cost.py --config "hardware_cost/config.json" --thermal-summary $thermalSummary --output "output/hbm2_hardware_cost/rtl_mapped"
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    & $python tools/validate_hbm2_hardware_cost.py --output "output/hbm2_hardware_cost/rtl_mapped" --thermal-summary $thermalSummary
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
  }
  Write-Host "RTL-to-3D analysis PASS. Mapping: $mapped; thermal: $ThermalOutput"
} finally { Pop-Location }
