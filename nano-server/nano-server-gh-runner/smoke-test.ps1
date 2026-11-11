<#
.SYNOPSIS
Smoke tests a built windows-nano-gh-runner image: pwsh, the powershell.exe stand-in, git (including submodule, which needs sh), the docker CLI, the runner, and the entrypoint's plan for several runners in one container.
.EXAMPLE
./nano-server/nano-server-gh-runner/smoke-test.ps1 -Image windows-nano-gh-runner:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

$script = @'
$ErrorActionPreference = 'Stop'
"pwsh $($PSVersionTable.PSVersion)"
# PowerShell comes from the base image and isn't pinned here (issue #71). 7.4 is the oldest supported PowerShell 7.
if ($PSVersionTable.PSVersion -lt [version]'7.4.0') { throw "pwsh $($PSVersionTable.PSVersion) is older than 7.4.0" }
& powershell.exe -NoProfile -Command '"powershell.exe shim ok"'
git --version
git init -q C:\t
git -C C:\t submodule foreach --recursive 'sh -c "true"'
if ($LASTEXITCODE) { throw "git submodule failed: $LASTEXITCODE" }
docker --version
& C:\actions-runner\bin\Runner.Listener.exe --version

# One runner by default, in the image's own folder, with the default labels and nothing optional
$env:RUNNER_NAME = 'smoke'
$one = & C:\actions-runner\start.ps1 -Mode Plan | ConvertFrom-Json
if ($one.Runners.Count -ne 1 -or $one.Runners[0].Name -ne 'smoke' -or $one.Runners[0].Directory -ne 'C:\actions-runner') {
    throw "unexpected default plan: $($one | ConvertTo-Json -Depth 3 -Compress)"
}
if (($one.ConfigOptions -join ' ') -ne '--unattended --replace --labels nanoserver,docker --work _work') {
    throw "unexpected default config options: $($one.ConfigOptions -join ' ')"
}

# Three runners: names, folders, and every optional setting
$env:RUNNER_COUNT = '3'
$env:RUNNER_LABELS = 'a,b'
$env:RUNNER_GROUP = 'grp'
$env:RUNNER_WORKDIR = 'w'
$env:RUNNER_EPHEMERAL = '1'
$env:RUNNER_DISABLE_UPDATE = 'true'
$env:RUNNER_NO_DEFAULT_LABELS = '1'
$three = & C:\actions-runner\start.ps1 -Mode Prepare | ConvertFrom-Json
if (($three.Runners.Name -join ',') -ne 'smoke,smoke-2,smoke-3') { throw "unexpected names: $($three.Runners.Name -join ',')" }
if (($three.Runners.Directory -join ',') -ne 'C:\actions-runner-1,C:\actions-runner-2,C:\actions-runner-3') {
    throw "unexpected folders: $($three.Runners.Directory -join ',')"
}
$expected = '--unattended --replace --labels a,b --work w --runnergroup grp --ephemeral --disableupdate --no-default-labels'
if (($three.ConfigOptions -join ' ') -ne $expected) { throw "unexpected config options: $($three.ConfigOptions -join ' ')" }

# Each runner's folder shares bin and externals through junctions, has its own scripts, and can run the runner
foreach ($dir in $three.Runners.Directory) {
    foreach ($shared in 'bin', 'externals') {
        $item = Get-Item (Join-Path $dir $shared)
        if ($item.LinkType -ne 'Junction') { throw "$dir\$shared is not a junction" }
    }
    foreach ($file in 'config.cmd', 'run.cmd') {
        if (-not (Test-Path (Join-Path $dir $file))) { throw "$dir\$file is missing" }
    }
    $version = & (Join-Path $dir 'bin\Runner.Listener.exe') --version
    if ($LASTEXITCODE -or -not $version) { throw "the runner doesn't start from $dir" }
}
'runner folders ok'

$env:RUNNER_COUNT = '0'
try { & C:\actions-runner\start.ps1 -Mode Plan; throw 'RUNNER_COUNT=0 was accepted' }
catch { if ($_ -notmatch 'RUNNER_COUNT must be') { throw } }
'runner count validation ok'
'@
# Encoded so quotes survive the trip through docker's command line
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
$out = docker run --rm --entrypoint 'C:\Program Files\PowerShell\7\pwsh.exe' $Image -NoProfile -OutputFormat Text -EncodedCommand $encoded
$code = $LASTEXITCODE
$out | Write-Host
if ($code) { throw "smoke test failed: $code" }
foreach ($marker in 'powershell.exe shim ok', 'runner folders ok', 'runner count validation ok') {
    if (-not ($out -match [regex]::Escape($marker))) { throw "smoke test output is missing '$marker'" }
}
