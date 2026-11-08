<#
.SYNOPSIS
Drains and stops the GitHub Actions runner containers running on this host.
.DESCRIPTION
Selects running containers whose image is windows-nano-gh-runner, or whose name matches -NamePattern.
Containers that belong to a Compose project (the runner fleet) are skipped unless -IncludeFleet.

For each one it reads the runner's registration name (RUNNER_NAME, or the container name), and stops the
container with docker stop once GitHub reports that runner idle, so no job is cut off. Runners GitHub
doesn't know count as idle. Runners still busy after -DrainMinutes are left running, and the script
throws, unless -Force, which stops them anyway.

Containers are only stopped, not removed, so a rollback can inspect them. -Remove deletes them as well.
Run it on the host, never from a workflow job: a job would stop its own runner.
.EXAMPLE
./ci/runner-fleet/Stop-ActionRunners.ps1 -WhatIf
.EXAMPLE
./ci/runner-fleet/Stop-ActionRunners.ps1 -DrainMinutes 90
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo = 'zippy1981/windows-nano-demos',
    [string]$NamePattern = "$env:COMPUTERNAME-nano*",
    [string]$ImagePattern = '*windows-nano-gh-runner*',
    [ValidateRange(0, 720)][int]$DrainMinutes = 60,
    [ValidateRange(1, 300)][int]$PollSeconds = 15,
    [ValidateRange(1, 600)][int]$StopTimeoutSeconds = 60,
    [switch]$IncludeFleet,
    [switch]$Force,
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'

function Get-RunnerContainer([string]$NamePattern, [string]$ImagePattern, [bool]$IncludeFleet) {
    $lines = docker ps --format '{{.Names}}|{{.Image}}|{{.Label "com.docker.compose.project"}}'
    if ($LASTEXITCODE) { throw "docker ps failed: $LASTEXITCODE" }
    foreach ($line in $lines) {
        $name, $image, $project = $line -split '\|', 3
        if (-not ($image -like $ImagePattern -or $name -like $NamePattern)) { continue }
        if ($project -and -not $IncludeFleet) { continue }
        $envVars = docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $name
        $runnerName = ($envVars | Where-Object { $_ -like 'RUNNER_NAME=*' } | Select-Object -First 1) -replace '^RUNNER_NAME=', ''
        [pscustomobject]@{ Container = $name; Image = $image; RunnerName = $runnerName ? $runnerName : $name }
    }
}

# Registration name -> busy, for every runner GitHub knows.
function Get-BusyMap([string]$Repo) {
    $json = gh api "repos/$Repo/actions/runners" --paginate --jq '.runners[] | {name, busy}'
    if ($LASTEXITCODE) { throw "listing the runners of $Repo failed: $LASTEXITCODE" }
    $map = @{}
    foreach ($line in $json) { $r = $line | ConvertFrom-Json; $map[$r.name] = [bool]$r.busy }
    $map
}

# Called only after the script's own ShouldProcess check.
function Invoke-RunnerStop($Target, [int]$StopTimeoutSeconds, [bool]$Remove) {
    docker stop -t $StopTimeoutSeconds $Target.Container | Out-Host
    if ($LASTEXITCODE) { throw "docker stop $($Target.Container) failed: $LASTEXITCODE" }
    if ($Remove) {
        docker container rm $Target.Container | Out-Host
        if ($LASTEXITCODE) { throw "removing $($Target.Container) failed: $LASTEXITCODE" }
        return 'Removed'
    }
    'Stopped'
}

# A script block, not a function, so ShouldProcess is the script's own (-WhatIf, -Confirm).
$stopTimeout = $StopTimeoutSeconds
$removeContainers = $Remove.IsPresent
$stopTarget = {
    param($Target, [string]$Note = '')
    $result = 'WhatIf'
    if ($PSCmdlet.ShouldProcess("$($Target.Container) (runner $($Target.RunnerName))", 'docker stop')) {
        $result = Invoke-RunnerStop $Target $stopTimeout $removeContainers
    }
    [pscustomobject]@{ Container = $Target.Container; RunnerName = $Target.RunnerName; Result = "$result$Note" }
}

$pending = [Collections.Generic.List[object]]@(Get-RunnerContainer $NamePattern $ImagePattern $IncludeFleet.IsPresent)
if (-not $pending.Count) {
    'No runner containers are running.' | Out-Host
    return
}
"Runner containers to stop: $($pending.Container -join ', ')" | Out-Host

$deadline = (Get-Date).AddMinutes($DrainMinutes)
$results = [Collections.Generic.List[object]]::new()
while ($pending.Count) {
    $busy = Get-BusyMap $Repo
    foreach ($target in @($pending)) {
        if ($busy[$target.RunnerName]) { continue }
        $results.Add((& $stopTarget $target))
        [void]$pending.Remove($target)
    }
    if (-not $pending.Count) { break }
    if ((Get-Date) -ge $deadline) {
        if (-not $Force) {
            $results | Format-Table -AutoSize | Out-Host
            throw "still busy after $DrainMinutes minutes, left running: $($pending.RunnerName -join ', '). Rerun later, or with -Force."
        }
        foreach ($target in @($pending)) { $results.Add((& $stopTarget $target ' (forced while busy)')) }
        break
    }
    "Waiting for busy runners to finish their jobs: $($pending.RunnerName -join ', ')" | Out-Host
    Start-Sleep -Seconds $PollSeconds
}
$results
