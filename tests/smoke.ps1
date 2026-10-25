$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\sysfetch.ps1'

$json = & $script -Json | Out-String
$data = $json | ConvertFrom-Json
if (-not $data.CPU -or -not $data.OS -or $null -eq $data.Memory) {
    throw 'JSON smoke test failed: required fields are missing.'
}

$plain = @(& $script -NoColor -NoLogo)
if ($plain.Count -lt 3) {
    throw 'Plain-text smoke test failed: too few output lines.'
}
$esc = [char]27
if (($plain -join "`n").Contains("$esc[")) {
    throw 'Plain-text smoke test failed: ANSI escape sequences were emitted.'
}

Write-Host 'sysfetch smoke tests passed.'
