<#
.SYNOPSIS
Smoke tests a built windows-nano-powershell image: tests/smoke.ps1 runs inside it, then checks that the default command is pwsh.
.EXAMPLE
./nano-server/nano-server-powershell/smoke-test.ps1 -Image windows-nano-powershell:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

# Passed as -EncodedCommand, because base64 survives the cmd /S /C entrypoint. Keep tests/smoke.ps1 under cmd's 8191-character limit.
$script = Get-Content -Raw -Path "$PSScriptRoot/tests/smoke.ps1"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
docker run --rm $Image pwsh -NoLogo -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encoded
if ($LASTEXITCODE) { throw "smoke test failed: $LASTEXITCODE" }

$version = docker run --rm $Image pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE) { throw "pwsh failed: $LASTEXITCODE" }
Write-Host "pwsh $version"
# PowerShell comes from the base image, so its version isn't pinned here (issue #71). 7.4 is the oldest supported
# PowerShell 7 (LTS) release, and the pinned modules need it.
$minimum = [version]'7.4.0'
if ([version](($version | Select-Object -Last 1) -replace '-.*$') -lt $minimum) { throw "pwsh $version is older than $minimum" }
$cmd = docker image inspect $Image --format '{{json .Config.Cmd}}'
if ($cmd -ne '["pwsh"]') { throw "unexpected default CMD: $cmd" }
