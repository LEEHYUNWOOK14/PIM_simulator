param(
    [Parameter(Mandatory=$true)][string]$Recipe,
    [switch]$Force,
    [switch]$OpenKLayout
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $env:LOCALAPPDATA "STOB_EDA\gds-merge\venv\Scripts\python.exe"
$klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Run tools\setup_gds_merge_environment.ps1 first." }
$arguments = @("tools\merge_final_rtl_gds.py", "--recipe", $Recipe)
if ($Force) { $arguments += "--force" }
Push-Location $root
try {
    & $python @arguments
    if ($LASTEXITCODE -ne 0) { throw "Final RTL GDS merge failed with exit $LASTEXITCODE" }
    if ($OpenKLayout) {
        $recipePath = if ([IO.Path]::IsPathRooted($Recipe)) { $Recipe } else { Join-Path $root $Recipe }
        $config = Get-Content -Raw -LiteralPath $recipePath | ConvertFrom-Json
        $gds = [Environment]::ExpandEnvironmentVariables($config.output.gds)
        $lyp = [Environment]::ExpandEnvironmentVariables($config.output.lyp)
        if (-not [IO.Path]::IsPathRooted($gds)) { $gds = Join-Path $root $gds }
        if (-not [IO.Path]::IsPathRooted($lyp)) { $lyp = Join-Path $root $lyp }
        Start-Process -FilePath $klayout -ArgumentList @($gds, "-l", $lyp)
    }
} finally { Pop-Location }
