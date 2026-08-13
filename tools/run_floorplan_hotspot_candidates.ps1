param(
    [string]$Thermal = "output/floorplan_optimization/thermal",
    [string]$Output = "output/floorplan_optimization/hotspot",
    [string]$WslDistro = "Ubuntu",
    [string]$HotSpot = "/home/chandler/.local/stob-eda/src/HotSpot/hotspot",
    [string]$HotSpotConfig = "/home/chandler/.local/stob-eda/src/HotSpot/examples/example1/example.config"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$thermalRoot = Join-Path $root $Thermal; $outputRoot = Join-Path $root $Output
New-Item -ItemType Directory -Force $outputRoot | Out-Null
foreach ($candidate in Get-ChildItem -LiteralPath $thermalRoot -Directory | Sort-Object Name) {
    $mapped = Join-Path $candidate.FullName "mapped_power.json"
    if (-not (Test-Path $mapped)) { continue }
    $destination = Join-Path $outputRoot $candidate.Name
    & $python tools/export_floorplan_hotspot.py --mapped-power $mapped --output $destination
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $drive = $destination.Substring(0,1).ToLowerInvariant(); $wslDestination = "/mnt/$drive" + $destination.Substring(2).Replace("\", "/")
    $command = "'$HotSpot' -c '$HotSpotConfig' -f '$wslDestination/candidate.flp' -p '$wslDestination/candidate.ptrace' -steady_file '$wslDestination/steady.txt' -ambient 300 -init_temp 300 -t_chip 0.0001 > '$wslDestination/run.log' 2>&1"
    & wsl.exe -d $WslDistro -- bash -lc $command
    if ($LASTEXITCODE -ne 0) { throw "HotSpot failed for $($candidate.Name)" }
}
& $python tools/collect_floorplan_hotspot_metrics.py --input $outputRoot --output (Join-Path (Split-Path $outputRoot) "hotspot_results.csv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "FLOORPLAN_HOTSPOT_CANDIDATES PASS output=$outputRoot"
