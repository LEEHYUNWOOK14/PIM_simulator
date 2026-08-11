param(
    [string]$GdsPath = "output\\output.gds"
)

$resolved = Resolve-Path -LiteralPath $GdsPath -ErrorAction SilentlyContinue
if (-not $resolved) {
    Write-Host "MISSING: $GdsPath"
    exit 1
}

$item = Get-Item -LiteralPath $resolved.Path
Write-Host "FOUND: $($item.FullName)"
Write-Host "SIZE: $($item.Length) bytes"
exit 0

