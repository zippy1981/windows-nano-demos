<#
.SYNOPSIS
Drains and stops the GitHub Actions runner containers running on this host.
.DESCRIPTION
Selects running containers whose image is windows-nano-gh-runner, or whose name matches -NamePattern.
Containers that belong to a Compose project (the runner fleet) are skipped unless -IncludeFleet.
-Container instead selects exactly the named containers, fleet or not (Set-RunnerCount.ps1 uses it).

For each one it reads the runner's registration name (RUNNER_NAME, or the container name) and repository
(RUNNER_URL, or -Repo), and stops the container with docker stop once GitHub reports that runner idle in
that repository, so no job is cut off. A container that runs several runners (RUNNER_COUNT) is stopped
once all of them are idle. Runners GitHub
doesn't know count as idle. Runners still busy after -DrainMinutes are left running, and the script
throws, unless -Force, which stops them anyway.

Containers are only stopped, not removed, so a rollback can inspect them. -Remove deletes them as well.
Run it on the host, never from a workflow job: a job would stop its own runner.
.EXAMPLE
./ci/runner-fleet/Stop-ActionRunners.ps1 -WhatIf
.EXAMPLE
./ci/runner-fleet/Stop-ActionRunners.ps1 -DrainMinutes 90
.EXAMPLE
./ci/runner-fleet/Stop-ActionRunners.ps1 -Container windows-nano-ci-runner5-1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo = 'zippy1981/windows-nano-demos',
    [string]$NamePattern = "$env:COMPUTERNAME-nano*",
    [string]$ImagePattern = '*windows-nano-gh-runner*',
    # Exactly these containers, instead of selecting by -NamePattern and -ImagePattern.
    [string[]]$Container,
    [ValidateRange(0, 720)][int]$DrainMinutes = 60,
    [ValidateRange(1, 300)][int]$PollSeconds = 15,
    [ValidateRange(1, 600)][int]$StopTimeoutSeconds = 60,
    [switch]$IncludeFleet,
    [switch]$Force,
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'

function Get-RunnerContainer([string]$NamePattern, [string]$ImagePattern, [bool]$IncludeFleet, [string[]]$Container,
    [string]$DefaultRepo) {
    $lines = docker ps --format '{{.Names}}|{{.Image}}|{{.Label "com.docker.compose.project"}}'
    if ($LASTEXITCODE) { throw "docker ps failed: $LASTEXITCODE" }
    foreach ($line in $lines) {
        $name, $image, $project = $line -split '\|', 3
        if ($Container) {
            if ($Container -notcontains $name) { continue }
        }
        elseif (-not ($image -like $ImagePattern -or $name -like $NamePattern) -or ($project -and -not $IncludeFleet)) {
            continue
        }
        $envVars = docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $name
        $runnerName = ($envVars | Where-Object { $_ -like 'RUNNER_NAME=*' } | Select-Object -First 1) -replace '^RUNNER_NAME=', ''
        $url = ($envVars | Where-Object { $_ -like 'RUNNER_URL=*' } | Select-Object -First 1) -replace '^RUNNER_URL=', ''
        $runnerRepo = if ($url -match '^https://github\.com/([^/]+/[^/]+?)/?$') { $Matches[1] } else { $DefaultRepo }
        if (-not $runnerName) { $runnerName = $name }
        # A container can run several runners (RUNNER_COUNT, see the runner image's start.ps1): the first has the
        # plain name, the rest add -2, -3 ... The container is idle only when all of them are.
        $count = ($envVars | Where-Object { $_ -like 'RUNNER_COUNT=*' } | Select-Object -First 1) -replace '^RUNNER_COUNT=', ''
        $runnerNames = @($runnerName) + @(if ($count -match '^\d+$' -and [int]$count -gt 1) { 2..[int]$count | ForEach-Object { "$runnerName-$_" } })
        [pscustomobject]@{ Container = $name; Image = $image; RunnerName = $runnerName; RunnerNames = $runnerNames; Repo = $runnerRepo }
    }
}

# "repository/registration name" -> busy, for every runner GitHub knows in those repositories.
function Get-BusyMap([string[]]$Repos) {
    $map = @{}
    foreach ($repo in $Repos) {
        $json = gh api "repos/$repo/actions/runners" --paginate --jq '.runners[] | {name, busy}'
        if ($LASTEXITCODE) { throw "listing the runners of $repo failed: $LASTEXITCODE" }
        foreach ($line in $json) { $r = $line | ConvertFrom-Json; $map["$repo/$($r.name)"] = [bool]$r.busy }
    }
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

$pending = [Collections.Generic.List[object]]@(Get-RunnerContainer $NamePattern $ImagePattern $IncludeFleet.IsPresent $Container $Repo)
if (-not $pending.Count) {
    'No runner containers are running.' | Out-Host
    return
}
$notRunning = $Container | Where-Object { $pending.Container -notcontains $_ }
if ($notRunning) { "Not running, so nothing to stop: $($notRunning -join ', ')" | Out-Host }
"Runner containers to stop: $($pending.Container -join ', ')" | Out-Host

$deadline = (Get-Date).AddMinutes($DrainMinutes)
$results = [Collections.Generic.List[object]]::new()
while ($pending.Count) {
    $busy = Get-BusyMap @($pending.Repo | Sort-Object -Unique)
    foreach ($target in @($pending)) {
        if ($target.RunnerNames | Where-Object { $busy["$($target.Repo)/$_"] }) { continue }
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
