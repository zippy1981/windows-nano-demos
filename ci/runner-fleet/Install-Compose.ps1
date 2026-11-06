<#
.SYNOPSIS
Downloads the pinned standalone docker compose binary, checks its SHA-256, and returns its path.
.DESCRIPTION
Neither the host nor the runner image has the Compose plugin (ADR 0015). This fetches
docker-compose-windows-x86_64.exe for the pinned version into -Destination\<version>\, verifies it
against the pinned SHA-256, and reuses it on later runs. A file that fails the check is deleted.
.EXAMPLE
$compose = ./ci/runner-fleet/Install-Compose.ps1
& $compose version
#>
[CmdletBinding()]
[OutputType([string])]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'windows-nano-demos\docker-compose')
)
$ErrorActionPreference = 'Stop'

# Bump both together, from the release's docker-compose-windows-x86_64.exe.sha256.
$version = 'v5.7.0'
$sha256 = 'f5dc759702aec5c0602e247aa861d14853216e3f481c4eaaf83621a035ecf92f'

$dir = Join-Path $Destination $version
$exe = Join-Path $dir 'docker-compose.exe'

function Test-Pinned([string]$Path) {
    (Test-Path $Path) -and (Get-FileHash $Path -Algorithm SHA256).Hash -eq $sha256
}

if (-not (Test-Pinned $exe)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $partial = "$exe.download"
    $url = "https://github.com/docker/compose/releases/download/$version/docker-compose-windows-x86_64.exe"
    curl.exe -fsSL --retry 3 -o $partial $url
    if ($LASTEXITCODE) { throw "downloading $url failed: $LASTEXITCODE" }
    if (-not (Test-Pinned $partial)) {
        Remove-Item -Force $partial
        throw "docker compose $version failed its SHA-256 check"
    }
    Move-Item -Force $partial $exe
}
$exe
