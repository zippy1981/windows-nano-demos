<#
.SYNOPSIS
Smoke tests a built windows-nano-powershell-sqlite-odbc image.
.DESCRIPTION
Checks that the Stackable SQLite ODBC driver is installed system-wide (its files, and its entry under
HKLM\SOFTWARE\ODBC\ODBCINST.INI, which every user sees), then runs tests/smoke-odbc.ps1 inside a
throwaway container. That script does real database work over ODBC: create, insert, update, delete
and read back, once in an in-memory database and once in a file database that a second connection
re-opens. Throws on the first failure.

The scripts are copied in with docker cp, because the CI runners are containers themselves and
cannot bind-mount the workspace.
.PARAMETER Image
The image to test.
.EXAMPLE
./nano-server/nano-server-powershell-sqlite-odbc/smoke-test.ps1 -Image windows-nano-powershell-sqlite-odbc:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

Write-Host "Smoke testing $Image"

# Runs one command in a fresh container and returns its output; throws if it exits non-zero
function Invoke-Image {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Command)
    $out = docker run --rm $Image @Command 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host "> $($Command -join ' ')"
    Write-Host $out.TrimEnd()
    if ($code) { throw "'$($Command -join ' ')' exited with $code" }
    return $out
}

$driver = Invoke-Image @('pwsh', '-NoLogo', '-NoProfile', '-Command', "Test-Path 'C:\Program Files\Stackable\ODBC\stackable_odbc_sqlite.dll'")
if ($driver -notmatch 'True') { throw 'stackable_odbc_sqlite.dll is not installed' }
Write-Host 'ok: driver DLL is installed'

# A system-wide registration lives in HKLM, where ContainerUser (the user that just ran the check
# above, and the image's default user) can see it. A per-user one would be under HKCU instead.
$registered = Invoke-Image @('pwsh', '-NoLogo', '-NoProfile', '-Command', "Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite' -Name Driver")
if ($registered -notmatch 'stackable_odbc_sqlite\.dll') { throw "the driver is not registered system-wide: $registered" }
Write-Host "ok: driver is registered system-wide ($($registered.Trim()))"

$cmd = docker image inspect $Image --format '{{json .Config.Cmd}}'
if ($cmd -ne '["pwsh"]') { throw "unexpected default CMD: $cmd" }
Write-Host 'ok: default command is pwsh'

# docker cp cannot touch a running Hyper-V container, so the container is created (not started),
# the scripts are copied in, and only then is it started with the test as its command.
$name = "powershell-sqlite-odbc-smoke-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    docker create --name $name $Image pwsh -NoLogo -NoProfile -File 'C:\smoke-odbc.ps1' | Out-Null
    if ($LASTEXITCODE) { throw 'creating the smoke container failed' }
    foreach ($script in 'OdbcSqlite.ps1', 'smoke-odbc.ps1') {
        docker cp (Join-Path $PSScriptRoot "tests/$script") "${name}:C:/$script" | Out-Null
        if ($LASTEXITCODE) { throw "docker cp of $script failed" }
    }
    docker start -a $name | Out-Host
    $code = docker inspect -f '{{.State.ExitCode}}' $name
    if ($code -ne '0') { throw "smoke-odbc.ps1 failed: container exit code $code" }
}
finally {
    docker rm -f $name 2>$null | Out-Null
}
Write-Host 'smoke test passed'
