param([ValidateSet("gds", "scad")][string]$View = "gds")

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = Join-Path $root "output\hbm2_arch"
if ($View -eq "gds") {
    $target = Join-Path $output "hbm2_pim_architecture.gds"
    $application = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
} else {
    $target = Join-Path $output "hbm2_pim_architecture.scad"
    $application = "$env:ProgramFiles\OpenSCAD\openscad.exe"
}
if (-not (Test-Path -LiteralPath $target)) { throw "Model not found: $target. Run tools\generate_hbm2_architecture.ps1 first." }
if (-not (Test-Path -LiteralPath $application)) { throw "Viewer not found: $application" }
Start-Process -FilePath $application -ArgumentList ('"{0}"' -f $target)

