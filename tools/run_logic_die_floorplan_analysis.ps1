param(
    [switch]$SkipExternalSolvers,
    [switch]$SkipRendering,
    [switch]$IncludeCurrentRtlPhysical,
    [string]$FinalGdsMergeRecipe,
    [int]$Seed = 235,
    [int]$Samples = 400,
    [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$resultRoot = Join-Path $root "reports\floorplan_optimization\results"
$logRoot = Join-Path $resultRoot "orchestration_logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not (Test-Path -LiteralPath $python)) { throw "Project Python not found: $python" }

$steps = [System.Collections.Generic.List[object]]::new()
function Assert-NativeSuccess {
    param([string]$Context)
    if ($LASTEXITCODE -ne 0) { throw "$Context failed with native exit code $LASTEXITCODE" }
}
function Invoke-AnalysisStep {
    param([string]$Name, [scriptblock]$Action)
    $started = Get-Date
    $log = Join-Path $logRoot ("{0}.log" -f $Name)
    try {
        & $Action *>&1 | Tee-Object -FilePath $log
        if ($LASTEXITCODE -ne 0) { throw "native exit code $LASTEXITCODE" }
        $status = "PASS"
    } catch {
        $status = "FAIL"
        $_ | Out-String | Add-Content -LiteralPath $log
        $steps.Add([ordered]@{name=$Name; status=$status; started_at=$started.ToString("o"); duration_s=[math]::Round(((Get-Date)-$started).TotalSeconds,3); log=$log.Substring($root.Length+1).Replace("\","/"); error=$_.Exception.Message})
        throw
    }
    $steps.Add([ordered]@{name=$Name; status=$status; started_at=$started.ToString("o"); duration_s=[math]::Round(((Get-Date)-$started).TotalSeconds,3); log=$log.Substring($root.Length+1).Replace("\","/")})
}

Push-Location $root
try {
    Invoke-AnalysisStep "01_architecture" { & tools\generate_hbm2_architecture.ps1 }
    Invoke-AnalysisStep "02_rtl_to_3d" { & tools\run_rtl_to_3d_analysis.ps1 -SkipHardwareCost }
    Invoke-AnalysisStep "03_hardware_cost" {
        & tools\run_hbm2_hardware_cost_analysis.ps1
        & $python -m unittest verification.hardware_cost_regression.test_hardware_cost_regression -v
        Assert-NativeSuccess "hardware-cost regression"
    }
    Invoke-AnalysisStep "04_floorplan_manifest" {
        & $python tools\generate_logic_die_floorplan_manifest.py
        Assert-NativeSuccess "floorplan manifest generation"
        & $python tools\validate_logic_die_floorplan.py
        Assert-NativeSuccess "floorplan manifest validation"
    }
    Invoke-AnalysisStep "05_candidate_exploration" {
        & $python tools\optimize_logic_die_floorplan.py --seed $Seed --samples $Samples
    }
    if (-not $SkipExternalSolvers) {
        Invoke-AnalysisStep "06_openroad_macro_proxies" { & tools\run_floorplan_openroad_proxies.ps1 -WslDistro $WslDistro }
        Invoke-AnalysisStep "07_reference_thermal" { & tools\run_floorplan_thermal_candidates.ps1 }
        Invoke-AnalysisStep "08_hotspot" { & tools\run_floorplan_hotspot_candidates.ps1 -WslDistro $WslDistro }
        Invoke-AnalysisStep "09_3dice" { & tools\run_floorplan_3dice_candidates.ps1 -WslDistro $WslDistro }
    }
    Invoke-AnalysisStep "10_candidate_comparison" { & $python tools\compare_floorplan_candidates.py }

    if (-not $SkipRendering) {
        Invoke-AnalysisStep "11_candidate_visualization" {
            $klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"
            $pvpython = Join-Path $env:LOCALAPPDATA "STOB_EDA\ParaView\ParaView-6.1.1-Windows-Python3.12-msvc2017-AMD64\bin\pvpython.exe"
            foreach ($candidate in Get-ChildItem output\floorplan_optimization\exploration\candidates -Filter "*.json" | Sort-Object Name) {
                $strategy = $candidate.BaseName
                $destination = Join-Path $root "output\floorplan_optimization\visualization\$strategy"
                $thermalField = Join-Path $root "output\floorplan_optimization\thermal\$strategy\temperature_field.npz"
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
                & $python tools\export_logic_die_floorplan_gds.py --manifest $candidate.FullName --output $destination --thermal-field $thermalField
                Assert-NativeSuccess "GDS export $strategy"
                $env:STOB_FLOORPLAN_GDS = Join-Path $destination "logic_die_floorplan.gds"
                $env:STOB_FLOORPLAN_VIS_MANIFEST = Join-Path $destination "visualization_manifest.json"
                $env:STOB_FLOORPLAN_LYP = Join-Path $destination "logic_die_floorplan.lyp"
                $env:STOB_FLOORPLAN_PNG = Join-Path $destination "klayout_fixed_camera.png"
                foreach ($script in @("check_logic_die_floorplan_gds.py", "render_floorplan_klayout.py")) {
                    $process = Start-Process -FilePath $klayout -ArgumentList @("-zz", "-r", (Join-Path $root "tools\$script")) -Wait -PassThru -WindowStyle Hidden
                    if ($process.ExitCode -ne 0) { throw "KLayout $script failed for $strategy with exit $($process.ExitCode)" }
                }
                $pvDir = Join-Path $destination "paraview"
                & $python tools\export_floorplan_paraview.py --manifest $candidate.FullName --thermal-field $thermalField --output $pvDir
                Assert-NativeSuccess "ParaView export $strategy"
            }
            $thermalVtu = Join-Path $root "output\floorplan_optimization\visualization\thermal_first\paraview\stack_temperature_z20_exaggerated.vtu"
            $figure1 = Join-Path $root "output\floorplan_optimization\visualization\paper_figures\figure_01_hbm_stack_3d.png"
            New-Item -ItemType Directory -Force -Path (Split-Path $figure1) | Out-Null
            & $pvpython tools\render_floorplan_paraview.py --input $thermalVtu --output $figure1
            Assert-NativeSuccess "ParaView paper render"
            & $python tools\generate_floorplan_paper_figures.py
            Assert-NativeSuccess "paper figure generation"
            Remove-Item Env:STOB_FLOORPLAN_GDS,Env:STOB_FLOORPLAN_VIS_MANIFEST,Env:STOB_FLOORPLAN_LYP,Env:STOB_FLOORPLAN_PNG -ErrorAction SilentlyContinue
        }
    }

    if ($IncludeCurrentRtlPhysical) {
        Invoke-AnalysisStep "12_current_rtl_through_global_route" {
            foreach ($stage in @("synth","do-floorplan","do-place","do-cts","do-route")) {
                & flow\run_flow.ps1 -Target $stage
            }
        }
    }
    if ($FinalGdsMergeRecipe) {
        Invoke-AnalysisStep "12_final_rtl_gds_merge" {
            & tools\run_final_rtl_gds_merge.ps1 -Recipe $FinalGdsMergeRecipe -Force
        }
    }
    # Phase-8 tests verify the evidence links themselves.  Publish an interim
    # summary/manifest first; the finally block replaces the summary with the
    # authoritative final state after the tests finish.
    [ordered]@{
        schema_version = "1.0"; generated_at = (Get-Date).ToString("o"); status = "RUNNING"
        seed = $Seed; samples = $Samples; current_rtl_physical_included = [bool]$IncludeCurrentRtlPhysical
        current_rtl_detailed_route_included = $false; steps = $steps
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $resultRoot "orchestration_results.json") -Encoding utf8
    & $python tools\collect_floorplan_generation_manifest.py
    if ($LASTEXITCODE -ne 0) { throw "interim generation manifest failed" }
    Invoke-AnalysisStep "13_floorplan_regression" {
        & $python -m unittest discover -s verification\floorplan_optimization -p "test_*.py" -v
    }
} finally {
    Pop-Location
    $summary = [ordered]@{
        schema_version = "1.0"
        generated_at = (Get-Date).ToString("o")
        status = if (($steps | Where-Object status -eq "FAIL").Count) { "FAIL" } else { "PASS" }
        seed = $Seed
        samples = $Samples
        current_rtl_physical_included = [bool]$IncludeCurrentRtlPhysical
        current_rtl_detailed_route_included = $false
        steps = $steps
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $resultRoot "orchestration_results.json") -Encoding utf8
}

& $python tools\collect_floorplan_generation_manifest.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "LOGIC_DIE_FLOORPLAN_ANALYSIS PASS manifest=output/floorplan_optimization/generation_manifest.json"
