param(
    [string]$WslDistro = "Ubuntu",
    [string]$OrfsRoot = "/home/chandler/OpenROAD-flow-scripts",
    [string]$RepoRoot = "",
    [string]$OpenRoadExe = "/home/chandler/.local/stob-eda/openroad/bin/openroad",
    [string]$YosysExe = "/home/chandler/.local/oss-cad-suite/bin/yosys",
    [ValidateSet("all", "synth", "floorplan", "place", "cts", "route", "finish", "do-floorplan", "do-place", "do-cts", "do-route", "do-finish")]
    [string]$Target = "all",
    [ValidateRange(1, 8)]
    [int]$OpenRoadThreads = 4,
    [ValidateRange(0, 64)]
    [int]$DetailedRouteEndIteration = 0
)

$ErrorActionPreference = "Stop"
$windowsRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $RepoRoot) {
    if ($windowsRepoRoot -notmatch '^([A-Za-z]):\\(.*)$') { throw "Expected an absolute Windows repository path." }
    $drive = $Matches[1].ToLowerInvariant()
    $RepoRoot = "/mnt/$drive/" + $Matches[2].Replace("\", "/")
}
$designConfig = "$RepoRoot/flow/designs/sky130hd/stob_pim2/config.mk"
$flowRoot = "$OrfsRoot/flow"
$resultGds = "$flowRoot/results/sky130hd/stob_pim2/base/6_final.gds"
$outputGds = "$RepoRoot/output/output.gds"
$makeTarget = if ($Target -eq "all") { "" } else { $Target }

$command = @"
set -e
cd $flowRoot
make DESIGN_CONFIG='$designConfig' STOB_REPO_ROOT='$RepoRoot' YOSYS_EXE='$YosysExe' OPENROAD_EXE='$OpenRoadExe' KLAYOUT_CMD=/usr/bin/klayout NUM_CORES=$OpenRoadThreads DETAILED_ROUTE_END_ITERATION=$DetailedRouteEndIteration MATCH_CELL_FOOTPRINT= SKIP_REPORT_METRICS=1 ENABLE_PLACE_REPAIR_TIMING=0 ENABLE_DPO=0 SKIP_CTS_REPAIR_TIMING=1 SKIP_INCREMENTAL_REPAIR=1 SKIP_ANTENNA_REPAIR=1 SKIP_ANTENNA_REPAIR_POST_DRT=1 RECOVER_POWER=0 -j1 $makeTarget
"@

if ($Target -eq "all" -or $Target -eq "finish") {
    $command += @"
cp -- '$resultGds' '$outputGds'
export STOB_FULL_PIM_GDS='$outputGds'
klayout -b -zz -r '$RepoRoot/tools/check_full_pim_gds.py'
"@
}

Write-Host "Running the sky130hd RTL-to-GDS flow in $WslDistro..."
& wsl.exe -d $WslDistro -- bash -c $command
if ($LASTEXITCODE -ne 0) {
    throw "OpenROAD flow failed with exit code $LASTEXITCODE."
}

$windowsOutput = Join-Path $windowsRepoRoot "output\output.gds"
if ($Target -ne "all" -and $Target -ne "finish") {
    Write-Host "OpenROAD-flow-scripts target '$Target' completed; GDS export was intentionally skipped."
    exit 0
}
$gds = Get-Item -LiteralPath $windowsOutput
$hash = Get-FileHash -LiteralPath $windowsOutput -Algorithm SHA256
Write-Host "GDS: $($gds.FullName)"
Write-Host "Size: $($gds.Length) bytes"
Write-Host "SHA256: $($hash.Hash)"
