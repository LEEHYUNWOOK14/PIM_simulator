param(
    [string]$KlayoutExe,
    [switch]$SkipOpenSCAD
)

$ErrorActionPreference = "Stop"

function Find-KLayout {
    param([string]$ExplicitPath)
    $candidates = @(
        $ExplicitPath,
        (Get-Command klayout.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "$env:APPDATA\KLayout\klayout_app.exe",
        "$env:ProgramFiles\KLayout\klayout.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "KLayout executable was not found. Install KLayout or pass -KlayoutExe."
}

$klayout = Find-KLayout $KlayoutExe
$installDir = Split-Path -Parent $klayout
$pythonLib = Get-ChildItem (Join-Path $installDir "lib") -Directory -Filter "python3.*" |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $pythonLib) {
    throw "KLayout embedded Python directory was not found below '$installDir\lib'."
}

$pythonVersion = $pythonLib.Name.Substring("python".Length)
$sitePackages = Join-Path $pythonLib.FullName "site-packages"
$requirements = Join-Path $PSScriptRoot "..\requirements-klayout-3d.txt"

$py = Get-Command py.exe -ErrorAction SilentlyContinue
if (-not $py) { throw "Python launcher (py.exe) is required to install KLayout dependencies." }

# Microsoft Store Python enables pip's --user option in a site config. It is
# incompatible with --target, so explicitly disable it for this invocation.
$oldPipUser = $env:PIP_USER
try {
    $env:PIP_USER = "no"
    & $py.Source "-$pythonVersion" -m pip install --upgrade --target $sitePackages -r $requirements
    if ($LASTEXITCODE -ne 0) { throw "Installing KLayout Python dependencies failed." }
} finally {
    $env:PIP_USER = $oldPipUser
}

if (-not $SkipOpenSCAD) {
    $openScad = Get-Command openscad.exe -ErrorAction SilentlyContinue
    if (-not $openScad -and (Test-Path "$env:ProgramFiles\OpenSCAD\openscad.exe")) {
        $openScad = Get-Item "$env:ProgramFiles\OpenSCAD\openscad.exe"
    }
    if (-not $openScad) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) { throw "OpenSCAD is missing and winget is unavailable. Install OpenSCAD manually." }
        & $winget.Source install --id OpenSCAD.OpenSCAD --exact --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) { throw "OpenSCAD installation failed." }
    }
}

$openScadDir = "$env:ProgramFiles\OpenSCAD"
if (Test-Path $openScadDir) { $env:PATH = "$openScadDir;$env:PATH" }
$oldKLayoutHome = $env:KLAYOUT_HOME
$smokeHome = Join-Path ([System.IO.Path]::GetTempPath()) "stob-klayout-3d-smoke"
New-Item -ItemType Directory -Path $smokeHome -Force | Out-Null
try {
    # Avoid autorunning the GUI-only gds3xtrude Salt macro in headless mode.
    $env:KLAYOUT_HOME = $smokeHome
    & $klayout -zz -r (Join-Path $PSScriptRoot "check_klayout_3d.py")
    if ($LASTEXITCODE -ne 0) { throw "KLayout 3D dependency smoke test failed." }
} finally {
    $env:KLAYOUT_HOME = $oldKLayoutHome
}

Write-Host "KLayout 3D environment is ready. Restart KLayout before using Tools > gds3xtrude."
