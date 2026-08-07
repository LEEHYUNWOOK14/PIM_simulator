param([switch]$Transient, [string]$Profile="uniform")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) { throw "Missing .venv. Create it and install requirements.txt first." }
$argsList = @("tools/run_hbm2_thermal.py", "--profile", $Profile)
if ($Transient) { $argsList += "--transient" }
& $python @argsList
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $python "tools/validate_hbm2_thermal.py"
exit $LASTEXITCODE
