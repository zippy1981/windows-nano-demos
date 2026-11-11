<#
.SYNOPSIS
Starts self-hosted runners for another repository, on the runner fleet's network and artifact cache.
.DESCRIPTION
A runner on a personal account serves exactly one repository, so the fleet's runners can't also take another
repository's jobs. This starts a separate compose project from compose.runners.yaml, one per repository, whose
runners join the fleet's network (Start-RunnerFleet.ps1 must have started it) and get the cache's address.
It gets a registration token with the gh CLI and runs compose up --wait. The runners register with --replace.
.EXAMPLE
./ci/runner-fleet/Start-RepoRunners.ps1 -Repo zippy1981/windows-nano-baseimages
.EXAMPLE
./ci/runner-fleet/Start-RepoRunners.ps1 -Repo zippy1981/windows-nano-baseimages -Count 3 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repo,
    [ValidateRange(1, 5)][int]$Count = 2,
    # The compose project. Defaults to the repository's name, for example windows-nano-baseimages.
    [string]$Project,
    # Registration names are this plus 1, 2 ... Defaults to <COMPUTERNAME>-base for windows-nano-baseimages, and
    # <COMPUTERNAME>-<repository name> otherwise.
    [string]$NamePrefix,
    # Runners in each container, as in Start-RunnerFleet.ps1: Count x RunnersPerContainer jobs at once.
    [ValidateRange(1, 16)][int]$RunnersPerContainer = 1,
    [string]$Labels = 'nanoserver,docker',
    [switch]$DisableUpdate,
    [string]$RunnerImage = 'windows-nano-gh-runner:2022',
    [string]$Network = 'windows-nano-ci',
    [string]$CacheIp = '172.31.250.10',
    [string]$ComposeExe
)
$ErrorActionPreference = 'Stop'

$repoName = ($Repo -split '/')[1]
if ($repoName -eq 'windows-nano-demos') { throw 'windows-nano-demos has the fleet itself: use Start-RunnerFleet.ps1' }
if (-not $Project) { $Project = $repoName.ToLowerInvariant() }
if ($Project -eq 'windows-nano-ci') { throw 'windows-nano-ci is the fleet''s project; pick another -Project' }
if (-not $NamePrefix) {
    $NamePrefix = if ($repoName -eq 'windows-nano-baseimages') { "$env:COMPUTERNAME-base" } else { "$env:COMPUTERNAME-$repoName" }
}
if (-not $ComposeExe) { $ComposeExe = & (Join-Path $PSScriptRoot 'Install-Compose.ps1') }
$composeFile = Join-Path $PSScriptRoot 'compose.runners.yaml'
$services = 1..$Count | ForEach-Object { "runner$_" }

docker network inspect $Network *> $null
if ($LASTEXITCODE) { throw "network $Network doesn't exist: start the fleet first with Start-RunnerFleet.ps1" }
docker image inspect $RunnerImage *> $null
if ($LASTEXITCODE) { throw "image $RunnerImage is not on this host; build it or pull it first" }

$env:FLEET_PROJECT = $Project
$env:FLEET_NETWORK = $Network
$env:CACHE_IP = $CacheIp
$env:RUNNER_REPO = $Repo
$env:RUNNER_NAME_PREFIX = $NamePrefix
$env:RUNNER_IMAGE = $RunnerImage
$env:RUNNERS_PER_CONTAINER = $RunnersPerContainer
$env:RUNNER_LABELS = $Labels
$env:RUNNER_DISABLE_UPDATE = $DisableUpdate ? '1' : ''

$names = $services | ForEach-Object { "$NamePrefix$($_ -replace '^runner')" }
if (-not $PSCmdlet.ShouldProcess("$($names -join ', ') for $Repo (project $Project)", 'compose up')) { return }

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
