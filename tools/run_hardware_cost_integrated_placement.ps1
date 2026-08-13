$ErrorActionPreference="Stop"
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  & wsl -e bash tools/run_hardware_cost_integrated_placement.sh
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
} finally { Pop-Location }

