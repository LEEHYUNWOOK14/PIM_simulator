param(
    [string]$GdsPath = "output\\output.gds",
    [string]$KlayoutExe
)

function Get-KLayoutPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        $resolved = Resolve-Path -LiteralPath $ExplicitPath -ErrorAction SilentlyContinue
        if ($resolved) { return $resolved.Path }
        if (Test-Path -LiteralPath $ExplicitPath) { return (Resolve-Path -LiteralPath $ExplicitPath).Path }
        throw "KLayout executable not found at '$ExplicitPath'."
    }

    $candidates = @()
    $candidates += (Get-Command klayout.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    $candidates += @(
        "$env:ProgramFiles\KLayout\klayout.exe",
        "$env:ProgramFiles\KLayout\bin\klayout.exe",
        "$env:ProgramFiles(x86)\KLayout\klayout.exe",
        "$env:ProgramFiles(x86)\KLayout\bin\klayout.exe",
        "$env:LOCALAPPDATA\Programs\KLayout\klayout.exe",
        "$env:LOCALAPPDATA\Programs\KLayout\bin\klayout.exe",
        "$env:APPDATA\KLayout\klayout_app.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not find klayout.exe. Pass -KlayoutExe with the full path."
}

$resolvedGds = Resolve-Path -LiteralPath $GdsPath -ErrorAction SilentlyContinue
if (-not $resolvedGds) {
    throw "GDS not found at '$GdsPath'. Put the OpenROAD result in output/output.gds or pass -GdsPath."
}
$klayoutPath = Get-KLayoutPath -ExplicitPath $KlayoutExe

# The gds3xtrude plug-in starts OpenSCAD by command name. winget does not
# always refresh PATH in an already-open terminal, so add its default path.
$openScadDir = "$env:ProgramFiles\OpenSCAD"
if ((Test-Path -LiteralPath $openScadDir) -and ($env:PATH -notlike "*$openScadDir*")) {
    $env:PATH = "$openScadDir;$env:PATH"
}

# Start-Process flattens ArgumentList into a single command line on Windows.
# Quote the GDS explicitly so workspace names containing spaces are preserved.
$quotedGds = '"' + $resolvedGds.Path.Replace('"', '\"') + '"'
Start-Process -FilePath $klayoutPath -ArgumentList $quotedGds
