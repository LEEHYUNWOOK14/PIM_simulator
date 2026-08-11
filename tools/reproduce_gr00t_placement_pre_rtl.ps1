param(
    [string]$Gr00tRepo = "",
    [string]$WslDistro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$workspaceParent = Split-Path $repoRoot -Parent
if (-not $Gr00tRepo) {
    $Gr00tRepo = Join-Path $workspaceParent "STOB_PIM_pure_layornorm"
}
$results = Join-Path $repoRoot "experiment\gr00t_placement\results"
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
$autoRebuiltForGlibc = $false

if (-not (Test-Path (Join-Path $Gr00tRepo "src\tests\Gr00tNormalizationTestCases.cpp"))) {
    throw "GR00T normalization repository is unavailable: $Gr00tRepo"
}

$gr00tWsl = (& wsl.exe -d $WslDistro -- wslpath -a -u $Gr00tRepo).Trim()
$resultsWsl = (& wsl.exe -d $WslDistro -- wslpath -a -u $results).Trim()
New-Item -ItemType Directory -Force -Path $results | Out-Null

Write-Host "Running the measured GR00T N1.7 normalization profiles..."
$gr00tTimer = [System.Diagnostics.Stopwatch]::StartNew()
function Invoke-Gr00tNormalization {
    & wsl.exe -d $WslDistro -- bash -lc @"
set -o pipefail
cd '$gr00tWsl'
/usr/bin/time -v ./sim --gtest_filter='Gr00tN17NormalizationFixture.*' --gtest_color=no 2>&1 | tee '$resultsWsl/gr00t_normalization_reproduction.log'
"@ | Out-Host
    return $LASTEXITCODE
}

$gr00tExit = Invoke-Gr00tNormalization
if ($gr00tExit -ne 0 -and
    (Select-String -Quiet -SimpleMatch "GLIBC_2.43" (Join-Path $results "gr00t_normalization_reproduction.log"))) {
    Copy-Item (Join-Path $results "gr00t_normalization_reproduction.log") `
        (Join-Path $results "gr00t_normalization_failure_glibc.log") -Force
    $autoRebuiltForGlibc = $true
    Write-Host "Rebuilding GR00T simulator for the active WSL glibc..."
    & wsl.exe -d $WslDistro -- bash -lc "cd '$gr00tWsl' && ~/.local/bin/scons -c && ~/.local/bin/scons -j `$(nproc)"
    if ($LASTEXITCODE -ne 0) { throw "GR00T simulator rebuild failed." }
    $gr00tExit = Invoke-Gr00tNormalization
}
if ($gr00tExit -ne 0) {
    throw "GR00T normalization reproduction failed. Rebuild sim as documented in the report."
}
$gr00tTimer.Stop()

Write-Host "Replaying the GR00T profile through the repository LogicDieScheduler..."
$replayTimer = [System.Diagnostics.Stopwatch]::StartNew()
$replayBinary = "/tmp/stob_gr00t_scheduler_replay"
& wsl.exe -d $WslDistro -- bash -lc @"
set -o pipefail
cd '$resultsWsl/../../..'
g++ -std=c++17 -O2 -Wall -Wextra -I. experiment/gr00t_placement/gr00t_scheduler_replay.cpp -o '$replayBinary'
'$replayBinary' experiment/gr00t_placement/results/gr00t_scheduler_replay.csv
"@ | Out-Host
if ($LASTEXITCODE -ne 0) { throw "GR00T LogicDieScheduler replay failed." }
$replayTimer.Stop()

Write-Host "Running placement unit tests and quantitative exploration..."
$analysisTimer = [System.Diagnostics.Stopwatch]::StartNew()
Push-Location $repoRoot
try {
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    python -m unittest discover -s experiment\gr00t_placement -p "test_*.py" -v
    $unitTestExit = $LASTEXITCODE
    python experiment\gr00t_placement\analyze_placement.py
    $analysisExit = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference
    if ($unitTestExit -ne 0) { throw "Placement unit tests failed." }
    if ($analysisExit -ne 0) { throw "Placement analysis failed." }
}
finally {
    $ErrorActionPreference = "Stop"
    Pop-Location
}
$analysisTimer.Stop()
$totalTimer.Stop()

$manifest = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    main_repo_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    main_repo_worktree_dirty = [bool](& git -C $repoRoot status --porcelain)
    logic_die_scheduler_sha256 = (Get-FileHash (Join-Path $repoRoot "src\LogicDieScheduler.h") -Algorithm SHA256).Hash.ToLower()
    scheduler_replay_source_sha256 = (Get-FileHash (Join-Path $repoRoot "experiment\gr00t_placement\gr00t_scheduler_replay.cpp") -Algorithm SHA256).Hash.ToLower()
    placement_analysis_sha256 = (Get-FileHash (Join-Path $repoRoot "experiment\gr00t_placement\analyze_placement.py") -Algorithm SHA256).Hash.ToLower()
    assumptions_sha256 = (Get-FileHash (Join-Path $repoRoot "experiment\gr00t_placement\assumptions.json") -Algorithm SHA256).Hash.ToLower()
    gr00t_repo_commit = (& git -C $Gr00tRepo rev-parse HEAD).Trim()
    wsl_distro = $WslDistro
    random_seed = 1701
    gr00t_test_seconds = [math]::Round($gr00tTimer.Elapsed.TotalSeconds, 3)
    scheduler_replay_seconds = [math]::Round($replayTimer.Elapsed.TotalSeconds, 3)
    placement_test_and_analysis_seconds = [math]::Round($analysisTimer.Elapsed.TotalSeconds, 3)
    total_seconds = [math]::Round($totalTimer.Elapsed.TotalSeconds, 3)
    auto_rebuilt_for_glibc = $autoRebuiltForGlibc
    commands = @(
        "./sim --gtest_filter='Gr00tN17NormalizationFixture.*' --gtest_color=no",
        "g++ ... gr00t_scheduler_replay.cpp && /tmp/stob_gr00t_scheduler_replay ...",
        "python -m unittest discover -s experiment\gr00t_placement -p test_*.py -v",
        "python experiment\gr00t_placement\analyze_placement.py",
        "python experiment\gr00t_placement\validate_artifacts.py"
    )
    final_recommendation = $false
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $results "reproduction_manifest.json")

$ErrorActionPreference = "Continue"
python experiment\gr00t_placement\validate_artifacts.py
$validationExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($validationExit -ne 0) { throw "Placement artifact validation failed." }

Write-Host "Pre-RTL results: $results"
