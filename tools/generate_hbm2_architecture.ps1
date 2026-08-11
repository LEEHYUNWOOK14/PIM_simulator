param(
    [string]$Config = "design\hbm2_architecture.json",
    [switch]$SkipKLayout,
    [switch]$SkipOpenSCAD
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Project Python not found: $python" }

$configPath = (Resolve-Path (Join-Path $root $Config)).Path
$output = Join-Path $root "output\hbm2_arch"
& $python (Join-Path $PSScriptRoot "generate_hbm2_architecture.py") --config $configPath --output $output
if ($LASTEXITCODE -ne 0) { throw "HBM2 architecture generation failed." }
& $python (Join-Path $PSScriptRoot "validate_hbm2_architecture.py") --config $configPath --output $output
if ($LASTEXITCODE -ne 0) { throw "HBM2 architecture validation failed." }
& $python (Join-Path $PSScriptRoot "test_hbm2_architecture_variants.py")
if ($LASTEXITCODE -ne 0) { throw "HBM2 4Hi/12Hi and multi-stack variant validation failed." }

if (-not $SkipKLayout) {
    $klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
    if (-not (Test-Path -LiteralPath $klayout)) { throw "KLayout not found: $klayout" }
    $oldKLayoutHome = $env:KLAYOUT_HOME
    $env:KLAYOUT_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "stob-hbm2-klayout-smoke"
    New-Item -ItemType Directory -Force -Path $env:KLAYOUT_HOME | Out-Null
    $env:STOB_HBM2_GDS = Join-Path $output "hbm2_pim_architecture.gds"
    $env:STOB_HBM2_MANIFEST = Join-Path $output "generation_manifest.json"
    try {
        & $klayout -zz -r (Join-Path $PSScriptRoot "check_hbm2_gds_klayout.py")
        if ($LASTEXITCODE -ne 0) { throw "KLayout headless GDS validation failed." }
    } finally {
        $env:KLAYOUT_HOME = $oldKLayoutHome
        Remove-Item Env:STOB_HBM2_GDS -ErrorAction SilentlyContinue
        Remove-Item Env:STOB_HBM2_MANIFEST -ErrorAction SilentlyContinue
    }
}

if (-not $SkipOpenSCAD) {
    $openscad = Get-Command openscad.exe -ErrorAction SilentlyContinue
    if (-not $openscad -and (Test-Path "$env:ProgramFiles\OpenSCAD\openscad.exe")) {
        $openscad = Get-Item "$env:ProgramFiles\OpenSCAD\openscad.exe"
    }
    if (-not $openscad) { throw "OpenSCAD not found. Run tools\setup_klayout_3d.ps1 first." }
    $csg = Join-Path $output "hbm2_pim_architecture.csg"
    $openScadExe = if ($openscad.Source) { $openscad.Source } else { $openscad.FullName }
    # OpenSCAD 2021.01 cannot reliably open non-ASCII Windows paths.
    $tempScad = Join-Path ([System.IO.Path]::GetTempPath()) "stob_hbm2_arch.scad"
    $tempCsg = Join-Path ([System.IO.Path]::GetTempPath()) "stob_hbm2_arch.csg"
    Copy-Item -LiteralPath (Join-Path $output "hbm2_pim_architecture.scad") -Destination $tempScad -Force
    $openScadProcess = Start-Process -FilePath $openScadExe -ArgumentList @(
        "-o", ('"{0}"' -f $tempCsg), ('"{0}"' -f $tempScad)
    ) -Wait -PassThru -WindowStyle Hidden
    if ($openScadProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempCsg)) { throw "OpenSCAD syntax/evaluation check failed." }
    Copy-Item -LiteralPath $tempCsg -Destination $csg -Force
}

Write-Host "HBM2 architecture generation and validation completed: $output"
