<#
.SYNOPSIS
Checks this host's Windows container setup and prints one pass, warn or fail row per check.
.DESCRIPTION
Read-only. Checks the OS build, the Docker engine (Windows mode, isolation, root directory), the Hyper-V and
Containers features, which LTSC base images this host can run, free disk space on the Docker root drive, host files
that build.cmd scripts copy, and whether the build download hosts answer. Every row has the evidence and, for a
warning or failure, the fix. Nothing is changed. The windows-host-doctor agent and the container-host-check skill
run it and explain only the rows that aren't pass.

Exits 1 when any check fails.
.PARAMETER Root
The repository root. Defaults to the folder above this script.
.PARAMETER Json
Write the rows as JSON instead of a table.
.PARAMETER SkipNetwork
Skip the download host checks.
.PARAMETER MinimumFreeGB
Free space on the Docker root drive below which the disk check fails. Below twice this, it warns.
.EXAMPLE
./scripts/Test-ContainerHost.ps1
.EXAMPLE
./scripts/Test-ContainerHost.ps1 -Json -SkipNetwork
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Json,
    [switch]$SkipNetwork,
    [int]$MinimumFreeGB = 20
)
$ErrorActionPreference = 'Stop'

# LTSC base image -> its Windows build
$ltscBuilds = [ordered]@{ '2019' = 17763; '2022' = 20348; '2025' = 26100 }
$downloadHosts = 'https://mcr.microsoft.com', 'https://hub.docker.com', 'https://github.com', 'https://nodejs.org', 'https://windows.php.net'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string]$Check,
        [ValidateSet('pass', 'warn', 'fail')][string]$Status,
        [string]$Evidence,
        [string]$Fix = ''
    )
    $results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Evidence = $Evidence; Fix = $Fix })
}

# OS: client SKUs run Windows containers with Hyper-V isolation only
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$hostBuild = [int]$os.BuildNumber
$isServer = $os.ProductType -ne 1
Add-Result 'OS' 'pass' "$($os.Caption) build $hostBuild ($(if ($isServer) { 'server: process isolation possible' } else { 'client: Hyper-V isolation' }))"

# Docker engine
$info = $null
$raw = docker info --format '{{json .}}' 2>$null
if ($LASTEXITCODE -or -not $raw) {
    Add-Result 'Docker engine' 'fail' 'docker info failed' 'Start Docker Desktop (or the docker service) and run the check again'
} else {
    $info = $raw | ConvertFrom-Json
    if ($info.OSType -ne 'windows') {
        Add-Result 'Docker engine' 'fail' "OSType is $($info.OSType)" "Switch to Windows containers: & `"`$env:ProgramFiles\Docker\Docker\DockerCli.exe`" -SwitchWindowsEngine (ask first)"
    } else {
        Add-Result 'Docker engine' 'pass' "$($info.ServerVersion), default isolation $($info.Isolation), root $($info.DockerRootDir)"
    }
}

# Windows features: listing them needs elevation, so a denial is a warning, not a guess
foreach ($feature in 'Containers', 'Microsoft-Hyper-V-All') {
    try {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop).State
        if ("$state" -eq 'Enabled') {
            Add-Result "Feature $feature" 'pass' 'Enabled'
        } else {
            Add-Result "Feature $feature" 'fail' "$state" "Enable-WindowsOptionalFeature -Online -FeatureName $feature -All (admin, then reboot)"
        }
    } catch {
        Add-Result "Feature $feature" 'warn' "couldn't read: $($_.Exception.Message.Trim())" 'Run the check from an elevated shell to see feature state'
    }
}

# Which LTSC bases this host runs with its default isolation
if ($info -and $info.OSType -eq 'windows') {
    foreach ($version in $ltscBuilds.Keys) {
        $baseBuild = $ltscBuilds[$version]
        $check = "Base ltsc$version ($baseBuild)"
        if ($baseBuild -gt $hostBuild) {
            Add-Result $check 'fail' "newer than host build $hostBuild" 'Build this version on a newer host or skip it locally'
        } elseif ($info.Isolation -eq 'process' -and $baseBuild -ne $hostBuild) {
            Add-Result $check 'warn' "process isolation needs build $hostBuild" 'Pass --isolation=hyperv for this version'
        } else {
            Add-Result $check 'pass' "runs with $($info.Isolation) isolation"
        }
    }

    # Disk: base images plus build cache take tens of GB
    $drive = (Split-Path -Qualifier $info.DockerRootDir).TrimEnd(':')
    $freeGB = [math]::Round((Get-PSDrive -Name $drive -PSProvider FileSystem).Free / 1GB, 1)
    $evidence = "$freeGB GB free on ${drive}:"
    if ($freeGB -lt $MinimumFreeGB) {
        Add-Result 'Disk' 'fail' $evidence 'Free space; remove your own experiments with the safe-docker-cleanup skill (never prune)'
    } elseif ($freeGB -lt 2 * $MinimumFreeGB) {
        Add-Result 'Disk' 'warn' $evidence 'Low for a full matrix build'
    } else {
        Add-Result 'Disk' 'pass' $evidence
    }
}

# Host files that build.cmd scripts copy. CI builds have no host files, so the fix is a servercore build stage.
$missing = [System.Collections.Generic.List[string]]::new()
$copied = 0
foreach ($script in Get-ChildItem -Path (Join-Path $Root 'nano-server'), (Join-Path $Root 'server-core') -Filter build.cmd -Recurse -Depth 1 -ErrorAction SilentlyContinue) {
    foreach ($line in Get-Content -LiteralPath $script.FullName) {
        if ($line -match '^\s*(rem|::)' -or $line -notmatch '(?i)\b(copy|xcopy|robocopy)\b') { continue }
        foreach ($match in [regex]::Matches($line, '(%\w+%|[A-Za-z]:)\\[^"\s]+')) {
            $copied++
            $path = [Environment]::ExpandEnvironmentVariables($match.Value)
            if (-not (Test-Path -LiteralPath $path)) { $missing.Add("$($script.Directory.Name): $path") }
        }
    }
}
if ($missing.Count) {
    Add-Result 'build.cmd host files' 'warn' ($missing -join '; ') 'Copy these from a servercore build stage instead of the host'
} else {
    Add-Result 'build.cmd host files' 'pass' $(if ($copied) { "$copied host files present" } else { 'no build.cmd copies host files' })
}

# Download hosts, from the host. A container-only failure is then a container DNS or proxy problem.
if (-not $SkipNetwork) {
    foreach ($url in $downloadHosts) {
        try {
            $null = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 15 -MaximumRedirection 5 -SkipHttpErrorCheck
            Add-Result "Network $url" 'pass' 'reachable'
        } catch {
            Add-Result "Network $url" 'fail' $_.Exception.Message 'Check DNS, proxy and firewall for this host (ask before changing them)'
        }
    }
}

if ($Json) {
    $results | ConvertTo-Json -Depth 3
} else {
    $results | Format-Table -AutoSize -Wrap | Out-String -Width 200
}
if ($results.Status -contains 'fail') { exit 1 }
