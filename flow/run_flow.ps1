param(
    [string]$WslDistro = "Ubuntu",
    [string]$OrfsRoot = "/home/chandler/OpenROAD-flow-scripts",
    [string]$RepoRoot = "/mnt/c/orfs",
    [ValidateRange(1, 8)]
    [int]$OpenRoadThreads = 4,
    [ValidateRange(0, 64)]
    [int]$DetailedRouteEndIteration = 0
)

$ErrorActionPreference = "Stop"
$designConfig = "$RepoRoot/flow/designs/sky130hd/stob_pim2/config.mk"
$openRoadRoot = "/home/chandler/.local/openroad-pi"
$yosys = "/home/chandler/.local/oss-cad-suite/bin/yosys"
$flowRoot = "$OrfsRoot/flow"
$resultGds = "$flowRoot/results/sky130hd/stob_pim2/base/6_final.gds"
$outputGds = "$RepoRoot/output/output.gds"

$command = @"
set -e
export LD_LIBRARY_PATH=/home/chandler/.local/miniconda3/envs/openroad-py310/lib:$openRoadRoot/usr/lib:$openRoadRoot/usr/lib64:$openRoadRoot/opt/or-tools/lib
cd $flowRoot
make DESIGN_CONFIG=$designConfig YOSYS_EXE=$yosys OPENROAD_EXE=$openRoadRoot/usr/bin/openroad KLAYOUT_CMD=/usr/bin/klayout NUM_CORES=$OpenRoadThreads DETAILED_ROUTE_END_ITERATION=$DetailedRouteEndIteration MATCH_CELL_FOOTPRINT= SKIP_REPORT_METRICS=1 ENABLE_PLACE_REPAIR_TIMING=0 ENABLE_DPO=0 SKIP_CTS_REPAIR_TIMING=1 SKIP_INCREMENTAL_REPAIR=1 SKIP_ANTENNA_REPAIR=1 SKIP_ANTENNA_REPAIR_POST_DRT=1 RECOVER_POWER=0 -j1
cp -- $resultGds $outputGds
export STOB_FULL_PIM_GDS=$outputGds
klayout -b -zz -r $RepoRoot/tools/check_full_pim_gds.py
"@

Write-Host "Running the sky130hd RTL-to-GDS flow in $WslDistro..."
& wsl.exe -d $WslDistro -- bash -c $command
if ($LASTEXITCODE -ne 0) {
    throw "OpenROAD flow failed with exit code $LASTEXITCODE."
}

$windowsOutput = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "output\output.gds"
$gds = Get-Item -LiteralPath $windowsOutput
$hash = Get-FileHash -LiteralPath $windowsOutput -Algorithm SHA256
Write-Host "GDS: $($gds.FullName)"
Write-Host "Size: $($gds.Length) bytes"
Write-Host "SHA256: $($hash.Hash)"
