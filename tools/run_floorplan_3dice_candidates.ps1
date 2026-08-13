param(
    [string]$Thermal = "output/floorplan_optimization/thermal",
    [string]$Output = "output/floorplan_optimization/3dice",
    [string]$WslDistro = "Ubuntu",
    [string]$ThreeDIce = "/home/chandler/.local/stob-eda/src/3d-ice/bin/3D-ICE-Emulator"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path; $python = Join-Path $root ".venv\Scripts\python.exe"
$thermalRoot = Join-Path $root $Thermal; $outputRoot = Join-Path $root $Output
New-Item -ItemType Directory -Force $outputRoot | Out-Null
foreach ($candidate in Get-ChildItem -LiteralPath $thermalRoot -Directory | Sort-Object Name) {
    $mapped = Join-Path $candidate.FullName "mapped_power.json"; if (-not (Test-Path $mapped)) { continue }
    $destination = Join-Path $outputRoot $candidate.Name
    & $python tools/export_floorplan_3dice.py --mapped-power $mapped --output $destination
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $drive = $destination.Substring(0,1).ToLowerInvariant(); $wslDestination = "/mnt/$drive" + $destination.Substring(2).Replace("\", "/")
    & wsl.exe -d $WslDistro -- bash -lc "cd '$wslDestination' && '$ThreeDIce' candidate.stk > run.log 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "3D-ICE failed for $($candidate.Name)" }
}
& $python tools/collect_floorplan_3dice_metrics.py --input $outputRoot --output (Join-Path (Split-Path $outputRoot) "3dice_results.csv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "FLOORPLAN_3DICE_CANDIDATES PASS output=$outputRoot"
