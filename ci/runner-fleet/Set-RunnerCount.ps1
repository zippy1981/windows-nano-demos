<#
.SYNOPSIS
Scales the compose runner projects up or down, for example to one runner each while the host is needed for
something else.
.DESCRIPTION
For each project (the fleet, windows-nano-ci, and the per-repository projects Start-RepoRunners.ps1 starts),
keeps runner1 to runner<Count> running and stops the rest:

- Runners above -Count are stopped with Stop-ActionRunners.ps1 -Container, which waits until GitHub reports each
  one idle, so no job is cut off (-DrainMinutes, -Force).
- Stopped runners at or below -Count are started again with docker start. They are still registered with GitHub,
  so no token is needed.

Stopped containers stay stopped through Docker and host restarts (restart: unless-stopped), until this script
or Start-RunnerFleet.ps1 / Start-RepoRunners.ps1 starts them. A runner the project never created can't be
started here, because registering it needs a token: the script names the start script to run instead.
The artifact cache is never touched.
.EXAMPLE
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 1 -WhatIf
.EXAMPLE
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 5
.EXAMPLE
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 2 -Project windows-nano-ci
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateRange(0, 5)][int]$Count,
    # Compose projects to scale. Defaults to every project on this host that has runner services.
    [string[]]$Project,
    [ValidateRange(0, 720)][int]$DrainMinutes = 60,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

# Every compose runner container, running or stopped: project, service (runner<N>), name and state.
$lines = docker ps -a --filter 'label=com.docker.compose.service' `
    --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}|{{.Names}}|{{.State}}'
if ($LASTEXITCODE) { throw "docker ps failed: $LASTEXITCODE" }
$runners = foreach ($line in $lines) {
    $proj, $service, $name, $state = $line -split '\|', 4
    if ($service -match '^runner(\d+)$') {
        [pscustomobject]@{ Project = $proj; Number = [int]$Matches[1]; Container = $name; State = $state }
    }
}
if (-not $Project) { $Project = @($runners.Project | Sort-Object -Unique) }
if (-not $Project) { throw 'no compose runner containers on this host: start them with Start-RunnerFleet.ps1' }

$toStop = [Collections.Generic.List[string]]::new()
$toStart = [Collections.Generic.List[string]]::new()
foreach ($proj in $Project) {
    $mine = @($runners | Where-Object Project -EQ $proj | Sort-Object Number)
    if (-not $mine) { Write-Warning "project $proj has no runner containers"; continue }
    foreach ($runner in $mine) {
        if ($runner.Number -gt $Count -and $runner.State -eq 'running') { $toStop.Add($runner.Container) }
        if ($runner.Number -le $Count -and $runner.State -ne 'running') { $toStart.Add($runner.Container) }
    }
    $missing = 1..$Count | Where-Object { $mine.Number -notcontains $_ }
    if ($Count -and $missing) {
        $script = if ($proj -eq 'windows-nano-ci') { 'Start-RunnerFleet.ps1 -Count' } else { 'Start-RepoRunners.ps1 -Count' }
        Write-Warning "$proj has no runner$($missing -join ', runner'); create them with $script $Count"
    }
}

if ($toStart.Count -and $PSCmdlet.ShouldProcess($toStart -join ', ', 'docker start')) {
    docker start @toStart | Out-Host
    if ($LASTEXITCODE) { throw "docker start failed: $LASTEXITCODE" }
}
if ($toStop.Count) {
    # Stop-ActionRunners.ps1 does its own -WhatIf and -Confirm for each container.
    $stopArgs = @{ Container = $toStop; DrainMinutes = $DrainMinutes; Force = $Force; WhatIf = $WhatIfPreference }
    & (Join-Path $PSScriptRoot 'Stop-ActionRunners.ps1') @stopArgs
}
if (-not ($toStart.Count -or $toStop.Count)) { "Already $Count runner(s) running in: $($Project -join ', ')" | Out-Host }
