param(
    [string]$OutputJson = "reports/floorplan_optimization/results/toolchain_smoke.json",
    [switch]$RunSolverExamples
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [string]$Command, [scriptblock]$Action)
    $previousPreference = $ErrorActionPreference
    try {
        # Several EDA tools emit progress on stderr even when they succeed.
        $ErrorActionPreference = "Continue"
        $text = (& $Action 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        $results.Add([pscustomobject]@{
            name = $Name; status = $(if ($code -eq 0) { "pass" } else { "fail" })
            exit_code = $code; command = $Command; output = $text
        })
    } catch {
        $results.Add([pscustomobject]@{
            name = $Name; status = "fail"; exit_code = -1
            command = $Command; output = $_.Exception.Message
        })
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

$klayout = "$env:APPDATA\KLayout\klayout_app.exe"
$openscad = "$env:LOCALAPPDATA\Programs\OpenSCAD\openscad.com"
$blender = "$env:LOCALAPPDATA\Programs\Blender\blender-5.2.0-windows-x64\blender.exe"
$pvpython = "$env:LOCALAPPDATA\STOB_EDA\ParaView\ParaView-6.1.1-Windows-Python3.12-msvc2017-AMD64\bin\pvpython.exe"
$python311 = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"

Add-Check "klayout_version" "$klayout -v" { & $klayout -v }
Add-Check "klayout_3d_python" "KLayout headless gds3xtrude dependency smoke" {
    $oldHome = $env:KLAYOUT_HOME
    $env:KLAYOUT_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "stob-klayout-3d-smoke"
    New-Item -ItemType Directory -Path $env:KLAYOUT_HOME -Force | Out-Null
    try { & $klayout -zz -r (Join-Path $PSScriptRoot "check_klayout_3d.py") }
    finally { $env:KLAYOUT_HOME = $oldHome }
}
Add-Check "openscad_version" "$openscad --version" { & $openscad --version }
Add-Check "blender_headless" "$blender --background --version" { & $blender --background --version }
Add-Check "paraview_python" "$pvpython --version" { & $pvpython --version }
Add-Check "python311" "$python311 --version" { & $python311 --version }
Add-Check "nvidia_gpu" "nvidia-smi --query-gpu=..." {
    & nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
}

$wslChecks = @'
set -e
/home/chandler/.local/stob-eda/openroad/bin/openroad -version
/home/chandler/.local/stob-eda/openroad/bin/openroad -no_init -exit
/home/chandler/.local/oss-cad-suite/bin/yosys -V
test -x /home/chandler/.local/stob-eda/src/HotSpot/hotspot
test -x /home/chandler/.local/stob-eda/src/3d-ice/bin/3D-ICE-Emulator
/home/chandler/.local/stob-eda/venvs/3d-ice/bin/python -c 'import numpy,matplotlib,shapely,rtree,gdspy; print(numpy.__version__,matplotlib.__version__,shapely.__version__,rtree.__version__,gdspy.__version__)'
! ldd /home/chandler/.local/stob-eda/openroad/bin/openroad | grep -q 'not found'
! ldd /home/chandler/.local/stob-eda/src/3d-ice/bin/3D-ICE-Emulator | grep -q 'not found'
'@
Add-Check "wsl_eda_stack" "WSL OpenROAD/Yosys/HotSpot/3D-ICE/Python checks" {
    & wsl.exe -d Ubuntu -- bash -c $wslChecks
}

if ($RunSolverExamples) {
    Add-Check "hotspot_example" "HotSpot example1 steady-state" {
        & wsl.exe -d Ubuntu -- bash -c "set -e; cd /home/chandler/.local/stob-eda/src/HotSpot/examples/example1; ../../hotspot -c example.config -f ev6.flp -p gcc.ptrace -materials_file example.materials -model_type block -steady_file /tmp/stob_hotspot.steady"
    }
    Add-Check "3d_ice_example" "3D-ICE example_steady.stk" {
        & wsl.exe -d Ubuntu -- bash -c "set -e; cd /home/chandler/.local/stob-eda/src/3d-ice/bin; OMP_NUM_THREADS=4 ./3D-ICE-Emulator example_steady.stk"
    }
}

$payload = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    host = $env:COMPUTERNAME
    repository = $repoRoot
    policy = "Large EDA tools and solver outputs live on remote-desktop local storage, not OneDrive."
    overall_status = $(if ($results.status -contains "fail") { "fail" } else { "pass" })
    checks = $results
}
$target = if ([System.IO.Path]::IsPathRooted($OutputJson)) { $OutputJson } else { Join-Path $repoRoot $OutputJson }
New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $target -Encoding utf8
$payload.checks | Format-Table name,status,exit_code -AutoSize
Write-Host "Result: $target"
if ($payload.overall_status -ne "pass") { exit 1 }
