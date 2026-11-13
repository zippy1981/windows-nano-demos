<#
.SYNOPSIS
Starts the runner fleet: the artifact cache and the self-hosted runners under docker compose.
.DESCRIPTION
Installs the pinned docker compose binary, refuses to start while hand-started runner containers that
use the same registration names are still running (stop them with Stop-ActionRunners.ps1), creates the
cache's host folders, gets a registration token with the gh CLI, and runs compose up --wait.
The runners register with --replace, so they take over the names of the runners they replace.
.EXAMPLE
./ci/runner-fleet/Start-RunnerFleet.ps1
.EXAMPLE
./ci/runner-fleet/Start-RunnerFleet.ps1 -Count 2 -RunnerImage windows-nano-gh-runner:2025
.EXAMPLE
./ci/runner-fleet/Start-RunnerFleet.ps1 -Count 2 -RunnersPerContainer 3
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo = 'zippy1981/windows-nano-demos',
    [ValidateRange(1, 5)][int]$Count = 5,
    [string]$NamePrefix = $env:COMPUTERNAME,
    # Runners in each container. A runner takes one job at a time, so the fleet runs Count x RunnersPerContainer
    # jobs at once. The second and later runners of a container register as <name>-2, <name>-3 ...
    [ValidateRange(1, 16)][int]$RunnersPerContainer = 1,
    [string]$Labels = 'nanoserver,docker',
    # The runners don't update themselves: the image's pinned runner version is the one that runs.
    [switch]$DisableUpdate,
    [string]$RunnerImage = 'windows-nano-gh-runner:2022',
    [string]$CacheImage = 'windows-nano-artifact-cache:2025',
    [string]$CacheRoot = 'C:\ProgramData\windows-nano-demos\artifact-cache',
    [string]$ComposeExe
)
$ErrorActionPreference = 'Stop'

if (-not $ComposeExe) { $ComposeExe = & (Join-Path $PSScriptRoot 'Install-Compose.ps1') }
$composeFile = Join-Path $PSScriptRoot 'compose.yaml'
$services = @('artifact-cache') + (1..$Count | ForEach-Object { "runner$_" })

# Two runners with one registration name would take each other's jobs and registration.
$names = 1..5 | ForEach-Object { if ($_ -eq 1) { "$NamePrefix-nano" } else { "$NamePrefix-nano$_" } }
$running = docker ps --format '{{.Names}}|{{.Label "com.docker.compose.project"}}' | ForEach-Object {
    $name, $project = $_ -split '\|', 2
    if (-not $project -and $names -contains $name) { $name }
}
if ($running) { throw "old runner containers are still running: $($running -join ', '). Stop them first with Stop-ActionRunners.ps1." }

foreach ($image in $RunnerImage, $CacheImage) {
    docker image inspect $image *> $null
    if ($LASTEXITCODE) { throw "image $image is not on this host; build it or pull it first" }
}

$env:RUNNER_REPO = $Repo
$env:RUNNER_NAME_PREFIX = $NamePrefix
$env:RUNNER_IMAGE = $RunnerImage
$env:RUNNERS_PER_CONTAINER = $RunnersPerContainer
$env:RUNNER_LABELS = $Labels
$env:RUNNER_DISABLE_UPDATE = $DisableUpdate ? '1' : ''
$env:CACHE_IMAGE = $CacheImage
$env:CACHE_ROOT = $CacheRoot

if (-not $PSCmdlet.ShouldProcess("$($services -join ', ') from $composeFile", 'compose up')) { return }

New-Item -ItemType Directory -Force (Join-Path $CacheRoot 'cache'), (Join-Path $CacheRoot 'caddy-data') | Out-Null
$env:RUNNER_TOKEN = gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token
if (-not $env:RUNNER_TOKEN) { throw "could not get a registration token for $Repo" }
try {
    & $ComposeExe -f $composeFile up -d --wait @services | Out-Host
    if ($LASTEXITCODE) { throw "compose up failed: $LASTEXITCODE" }
}
finally {
    Remove-Item Env:RUNNER_TOKEN
}
& $ComposeExe -f $composeFile ps | Out-Host
