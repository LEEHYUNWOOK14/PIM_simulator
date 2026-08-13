param(
    [string]$Candidates = "output/floorplan_optimization/exploration/candidates",
    [string]$Output = "output/floorplan_optimization/thermal"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$candidateRoot = Join-Path $root $Candidates
$outputRoot = Join-Path $root $Output
New-Item -ItemType Directory -Force $outputRoot | Out-Null

& $python tools/validate_hbm2_thermal.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach ($candidate in Get-ChildItem -LiteralPath $candidateRoot -Filter "*.json" | Sort-Object Name) {
    $destination = Join-Path $outputRoot $candidate.BaseName
    New-Item -ItemType Directory -Force $destination | Out-Null
    $mapped = Join-Path $destination "mapped_power.json"
    & $python tools/floorplan_manifest_to_mapped_power.py --manifest $candidate.FullName --output $mapped
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $python tools/run_hbm2_thermal.py --mapped-power $mapped --output (Resolve-Path $destination).Path
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $python tools/collect_floorplan_thermal_metrics.py --input $outputRoot --output (Join-Path (Split-Path $outputRoot) "thermal_results.csv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "FLOORPLAN_THERMAL_CANDIDATES PASS output=$outputRoot"
