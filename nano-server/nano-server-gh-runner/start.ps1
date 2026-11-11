<#
.SYNOPSIS
Container entrypoint for the runner image: registers the runner, or several runners, on first start, then runs them.
.DESCRIPTION
A GitHub Actions runner takes one job at a time, so a container that should take several jobs at once runs
several runners. RUNNER_COUNT sets how many (default 1):

- With one runner, it is RUNNER_NAME, in C:\actions-runner.
- With several, they are RUNNER_NAME, RUNNER_NAME-2, RUNNER_NAME-3 ... Each has its own folder (C:\actions-runner-1,
  C:\actions-runner-2 ...) with its own registration, _work and _diag. The bin and externals folders are junctions
  to C:\actions-runner, which then runs nothing itself, so a runner costs no disk space. The runner's own updater
  handles a junction bin: it downloads the new version into the runner's folder and points the junction at it, so
  each runner updates on its own and the shared folder never changes under a running job.

Registrations are kept in the container's filesystem, so `docker restart` reuses them without a new token.
With several runners, one that exits is started again after a few seconds, and the others keep their jobs.

Environment variables:
  RUNNER_URL, RUNNER_TOKEN   Repository or organization URL and a registration token. Needed for the first start.
  RUNNER_NAME                Registration name. Defaults to the container's host name.
  RUNNER_LABELS              Extra labels. Defaults to nanoserver,docker.
  RUNNER_COUNT               Runners in this container, 1 to 16. Defaults to 1.
  RUNNER_GROUP               Runner group, for organization runners.
  RUNNER_WORKDIR             Work folder, relative to each runner's folder. Defaults to _work.
  RUNNER_EPHEMERAL           1: each runner takes one job and unregisters. The container exits when all are done.
  RUNNER_DISABLE_UPDATE      1: the runner doesn't update itself. Rebuild the image to update it.
  RUNNER_NO_DEFAULT_LABELS   1: don't add the self-hosted, Windows and X64 labels.
.EXAMPLE
pwsh -File C:\actions-runner\start.ps1
.EXAMPLE
pwsh -File C:\actions-runner\start.ps1 -Mode Plan
#>
[CmdletBinding()]
param(
    # Run registers and runs the runners. Plan prints, as JSON, the runners this environment asks for and changes
    # nothing. Prepare also creates the extra runners' folders, but registers nothing. Neither needs a token.
    [ValidateSet('Run', 'Plan', 'Prepare')][string]$Mode = 'Run'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Test-Flag([string]$Value) { $Value -match '^(1|true|yes|on)$' }

# The runners this container should run: registration name and folder for each.
function Get-RunnerPlan {
    $count = 1
    if ($env:RUNNER_COUNT -and -not ([int]::TryParse($env:RUNNER_COUNT, [ref]$count) -and $count -ge 1 -and $count -le 16)) {
        throw "RUNNER_COUNT must be a number from 1 to 16, not '$env:RUNNER_COUNT'"
    }
    $name = $env:RUNNER_NAME ? $env:RUNNER_NAME : $env:COMPUTERNAME
    foreach ($number in 1..$count) {
        [pscustomobject]@{
            Name      = $number -eq 1 ? $name : "$name-$number"
            Directory = $count -eq 1 ? $PSScriptRoot : "$PSScriptRoot-$number"
        }
    }
}

# config.cmd arguments shared by every runner in the container, without the URL, token and name.
function Get-ConfigOption {
    $labels = $env:RUNNER_LABELS ? $env:RUNNER_LABELS : 'nanoserver,docker'
    $work = $env:RUNNER_WORKDIR ? $env:RUNNER_WORKDIR : '_work'
    $options = @('--unattended', '--replace', '--labels', $labels, '--work', $work)
    if ($env:RUNNER_GROUP) { $options += @('--runnergroup', $env:RUNNER_GROUP) }
    if (Test-Flag $env:RUNNER_EPHEMERAL) { $options += '--ephemeral' }
    if (Test-Flag $env:RUNNER_DISABLE_UPDATE) { $options += '--disableupdate' }
    if (Test-Flag $env:RUNNER_NO_DEFAULT_LABELS) { $options += '--no-default-labels' }
    $options
}

# One of several runners' folder: its own scripts and state, with bin and externals shared through junctions. The runner
# takes its root from the folder it is started in, not from where the junction points.
function Initialize-RunnerDirectory([string]$Directory) {
    if ($Directory -eq $PSScriptRoot -or (Test-Path (Join-Path $Directory 'config.cmd'))) { return }
    $null = New-Item -ItemType Directory -Force $Directory
    foreach ($shared in 'bin', 'externals') {
        $null = New-Item -ItemType Junction -Path (Join-Path $Directory $shared) -Target (Join-Path $PSScriptRoot $shared)
    }
    Copy-Item (Join-Path $PSScriptRoot '*.cmd'), (Join-Path $PSScriptRoot '*.template') $Directory
}

function Register-Runner($Runner, [string[]]$Options) {
    if (Test-Path (Join-Path $Runner.Directory '.runner')) { return }
    if (-not $env:RUNNER_URL -or -not $env:RUNNER_TOKEN) {
        throw 'RUNNER_URL and RUNNER_TOKEN must be set for the first start'
    }
    & (Join-Path $Runner.Directory 'config.cmd') @Options --url $env:RUNNER_URL --token $env:RUNNER_TOKEN --name $Runner.Name | Out-Host
    if ($LASTEXITCODE) { throw "registering $($Runner.Name) failed: $LASTEXITCODE" }
}

function Invoke-Runner($Runner) {
    $process = Start-Process -FilePath (Join-Path $Runner.Directory 'run.cmd') -WorkingDirectory $Runner.Directory -NoNewWindow -PassThru
    # Reading the handle now is what makes ExitCode available after the process exits
    $null = $process.Handle
    $process
}

$runners = @(Get-RunnerPlan)
$options = @(Get-ConfigOption)
if ($Mode -ne 'Run') {
    if ($Mode -eq 'Prepare') { foreach ($runner in $runners) { Initialize-RunnerDirectory $runner.Directory } }
    [pscustomobject]@{ Runners = $runners; ConfigOptions = $options } | ConvertTo-Json -Depth 3
    return
}

foreach ($runner in $runners) {
    Initialize-RunnerDirectory $runner.Directory
    Register-Runner $runner $options
}
docker version --format 'Connected to docker {{.Server.Version}} ({{.Server.Os}})'

if ($runners.Count -eq 1) {
    & .\run.cmd
    exit $LASTEXITCODE
}

# Several runners: all write to the container's log. An ephemeral runner is done when it exits. Any other runner
# that exits is started again, so one runner's crash or self-update never ends the others' jobs.
$ephemeral = Test-Flag $env:RUNNER_EPHEMERAL
$processes = @{}
foreach ($runner in $runners) { $processes[$runner.Name] = Invoke-Runner $runner }
"Started $($runners.Count) runners: $($runners.Name -join ', ')"
while ($processes.Count) {
    Start-Sleep -Seconds 5
    foreach ($runner in $runners) {
        $process = $processes[$runner.Name]
        if (-not $process -or -not $process.HasExited) { continue }
        if ($ephemeral) {
            "Runner $($runner.Name) finished (exit $($process.ExitCode))"
            $processes.Remove($runner.Name)
        }
        else {
            "Runner $($runner.Name) exited ($($process.ExitCode)); starting it again"
            $processes[$runner.Name] = Invoke-Runner $runner
        }
    }
}
exit 0
