<#
.SYNOPSIS
Tests the runner fleet's Compose files end to end, without registering any runner.
.DESCRIPTION
Validates compose.yaml alone and with compose.ci.yaml. Then, under a throwaway project on its own subnet:
- builds the artifact cache image (unless -CacheImage is given) and starts it with throwaway volumes;
- downloads an artifact through it twice from a nanoserver client, by its fixed address (MISS, then HIT);
- restarts it, and checks that the address is unchanged and the artifact is still a HIT;
- runs runner1 with compose.ci.yaml's connectivity check: docker pipe, cache by address and by name, GitHub.
Everything is removed at the end, including volumes and the network, and the cache image if this script built it.
.EXAMPLE
./ci/runner-fleet/test-compose.ps1 -ComposeExe (./ci/runner-fleet/Install-Compose.ps1)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ComposeExe,
    [string]$Project = 'ci-compose-' + [guid]::NewGuid().ToString('n').Substring(0, 8),
    [string]$CacheImage,
    [string]$RunnerImage = 'windows-nano-gh-runner:2022',
    [string]$ClientImage = 'mcr.microsoft.com/windows/nanoserver:ltsc2025-amd64',
    [string]$Subnet = '172.31.251.0/24',
    [string]$Gateway = '172.31.251.1',
    [string]$CacheIp = '172.31.251.10'
)
$ErrorActionPreference = 'Stop'

$composeFile = Join-Path $PSScriptRoot 'compose.yaml'
$ciFile = Join-Path $PSScriptRoot 'compose.ci.yaml'
$builtImage = $null
if (-not $CacheImage) {
    $CacheImage = "windows-nano-artifact-cache:$Project"
    $builtImage = $CacheImage
}
$env:FLEET_PROJECT = $Project
$env:FLEET_NETWORK = $Project
$env:FLEET_SUBNET = $Subnet
$env:FLEET_GATEWAY = $Gateway
$env:CACHE_IP = $CacheIp
$env:CACHE_IMAGE = $CacheImage
$env:RUNNER_IMAGE = $RunnerImage
$env:RUNNER_NAME_PREFIX = $Project
$artifact = 'https://www.7-zip.org/a/7zr.exe'

function Invoke-Compose {
    & $ComposeExe -f $composeFile -f $ciFile @args | Out-Host
    if ($LASTEXITCODE) { throw "compose $($args -join ' ') failed: $LASTEXITCODE" }
}

function Get-CacheContainer {
    $id = (& $ComposeExe -f $composeFile -f $ciFile ps -q artifact-cache | Out-String).Trim()
    if (-not $id) { throw 'the artifact-cache service has no container' }
    $id
}

# Downloads the artifact through the cache's fixed address and returns the cache status of the final response.
$probeImage = $ClientImage
function Get-CachedDownload([string]$Label, [string]$Client = $probeImage) {
    $uri = [uri]$artifact
    $script = "curl.exe -fsS -o C:\root.crt http://${CacheIp}:8080/root.crt && curl.exe -fsSL --resolve $($uri.Host):443:$CacheIp --cacert C:\root.crt --ssl-revoke-best-effort -o NUL -D - $artifact"
    $headers = docker run --rm --name "$Project-$Label" --network $Project $Client cmd /S /C $script | Out-String
    if ($LASTEXITCODE) { throw "client download $Label failed: $LASTEXITCODE" }
    $last = @($headers -split '(?m)^(?=HTTP/)' | Where-Object { $_.Trim() })[-1]
    $status = [regex]::Match($last, '(?im)^Cache-Status:\s*(.+?)\s*$').Groups[1].Value
    if ($status -match ';\s*hit') { 'HIT' } elseif ($status -match 'fwd=') { 'MISS' } else { "UNKNOWN ($status)" }
}

function Assert-Equal($Expected, $Actual, [string]$What) {
    if ($Expected -ne $Actual) { throw "$What should be $Expected, was $Actual" }
    "$What -> $Actual" | Out-Host
}

try {
    # The fleet file must also validate on its own, as Start-RunnerFleet.ps1 uses it.
    & $ComposeExe -f $composeFile config --quiet
    if ($LASTEXITCODE) { throw "compose.yaml is not valid: $LASTEXITCODE" }
    Invoke-Compose config --quiet
    'compose.yaml and compose.yaml + compose.ci.yaml are valid' | Out-Host

    if ($builtImage) {
        docker build --memory 4g -t $builtImage (Join-Path $PSScriptRoot '..\..\nano-server\nano-server-artifact-cache') | Out-Host
        if ($LASTEXITCODE) { throw "building $builtImage failed: $LASTEXITCODE" }
    }

    Invoke-Compose up -d --wait artifact-cache
    $cache = Get-CacheContainer
    $ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cache).Trim()
    Assert-Equal $CacheIp $ip 'cache address'
    Assert-Equal 'MISS' (Get-CachedDownload 'first') 'first download'
    Assert-Equal 'HIT' (Get-CachedDownload 'second') 'second download'

    Invoke-Compose restart artifact-cache
    Invoke-Compose up -d --wait artifact-cache
    $ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $cache).Trim()
    Assert-Equal $CacheIp $ip 'cache address after restart'
    Assert-Equal 'HIT' (Get-CachedDownload 'third') 'download after restart'

    Invoke-Compose up -d runner1
    $runner = (& $ComposeExe -f $composeFile -f $ciFile ps -a -q runner1 | Out-String).Trim()
    $exit = (docker wait $runner | Out-String).Trim()
    docker logs $runner 2>&1 | Out-Host
    Assert-Equal '0' $exit 'runner1 connectivity check exit code'
    'compose test passed' | Out-Host
}
finally {
    & $ComposeExe -f $composeFile -f $ciFile down -v --remove-orphans 2>&1 | Out-Host
    if ($builtImage) { docker rmi $builtImage 2>$null | Out-Null }
}
