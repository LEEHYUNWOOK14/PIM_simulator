param(
    [string]$Candidates = "output/floorplan_optimization/exploration/candidates",
    [string]$Output = "output/floorplan_optimization/openroad_proxy",
    [string]$OpenRoad = "/home/chandler/.local/stob-eda/openroad/bin/openroad",
    [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$candidateRoot = if ([IO.Path]::IsPathRooted($Candidates)) { $Candidates } else { Join-Path $root $Candidates }
$outputRoot = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $root $Output }
New-Item -ItemType Directory -Force $outputRoot | Out-Null
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($candidate in Get-ChildItem -LiteralPath $candidateRoot -Filter "*.json" | Sort-Object Name) {
    $strategy = $candidate.BaseName
    $destination = Join-Path $outputRoot $strategy
    & $python tools/export_floorplan_openroad_proxy.py --manifest $candidate.FullName --output $destination
    if ($LASTEXITCODE -ne 0) { $failures.Add("${strategy}: export") ; continue }
    $tcl = (Resolve-Path (Join-Path $destination "run_openroad.tcl")).Path
    $drive = $tcl.Substring(0, 1).ToLowerInvariant()
    $wslTcl = "/mnt/$drive" + $tcl.Substring(2).Replace("\", "/")
    $log = Join-Path $destination "run.log"
    $logDrive = $log.Substring(0, 1).ToLowerInvariant()
    $wslLog = "/mnt/$logDrive" + $log.Substring(2).Replace("\", "/")
    $command = "'$OpenRoad' -no_init '$wslTcl' > '$wslLog' 2>&1"
    & wsl.exe -d $WslDistro -- bash -c $command
    $exitCode = $LASTEXITCODE
    Write-Host "OpenROAD proxy $strategy exit=$exitCode log=$log"
    if ($exitCode -ne 0) { $failures.Add("${strategy}: OpenROAD exit $exitCode") }
}

& $python tools/collect_floorplan_openroad_proxy_metrics.py --input $outputRoot --output (Join-Path $outputRoot "openroad_proxy_metrics.csv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 2
}
Write-Host "FLOORPLAN_OPENROAD_PROXIES PASS output=$outputRoot"
