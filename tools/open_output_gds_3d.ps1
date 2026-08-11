param(
    [string]$MacroPath = "design\sky130hd_3d.py",
    [string]$ViewName = "SKY130 routed logic die"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$gds = Join-Path $windowsRoot "output\output.gds"
$macro = Join-Path $windowsRoot $MacroPath
$log = Join-Path $windowsRoot "output\klayout_3d.log"
$klayout = Join-Path $env:APPDATA "KLayout\klayout_app.exe"

if (-not (Test-Path -LiteralPath $gds)) {
    throw "GDS not found: $gds"
}
if (-not (Test-Path -LiteralPath $macro)) {
    throw "SKY130 2.5D macro not found: $macro"
}
if (-not (Test-Path -LiteralPath $klayout)) {
    throw "Native KLayout not found: $klayout"
}

Write-Host "Opening $ViewName in native KLayout..."
if ($MacroPath -eq "design\hbm2_logic_3d.py") {
    Write-Host "Guide: design\hbm2_klayout_3d_guide.md"
}
$env:STOB_REPO_ROOT = $windowsRoot.Path
$process = Start-Process -FilePath $klayout -ArgumentList @(
    "-e",
    "-k",
    ('"{0}"' -f $log),
    ('"{0}"' -f $gds),
    "-rr",
    ('"{0}"' -f $macro)
) -PassThru

# KLayout asks whether to show only the top cell. Answer it without stealing focus.
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
for ($attempt = 0; $attempt -lt 100 -and -not $process.HasExited; $attempt++) {
    $process.Refresh()
    if ($process.MainWindowTitle -eq "Tip" -and $process.MainWindowHandle -ne [IntPtr]::Zero) {
        $tip = [System.Windows.Automation.AutomationElement]::FromHandle(
            $process.MainWindowHandle
        )
        $controls = $tip.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        $yes = $null
        for ($index = 0; $index -lt $controls.Count; $index++) {
            $control = $controls.Item($index)
            if ($control.Current.ControlType -eq [System.Windows.Automation.ControlType]::CheckBox) {
                $toggle = $control.GetCurrentPattern(
                    [System.Windows.Automation.TogglePattern]::Pattern
                )
                if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::Off) {
                    $toggle.Toggle()
                }
            }
            if ($control.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
                $control.Current.Name -eq "Yes") {
                $yes = $control
            }
        }
        if ($null -ne $yes) {
            $invoke = $yes.GetCurrentPattern(
                [System.Windows.Automation.InvokePattern]::Pattern
            )
            $invoke.Invoke()
            break
        }
    }
    Start-Sleep -Milliseconds 100
}
