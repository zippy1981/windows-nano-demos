<#
.SYNOPSIS
Smoke tests a built windows-nano-combined-tools image: runs the baked-in tests, checks the licence files.

.DESCRIPTION
C:\tests\run-tests.cmd in the image writes TAP and exits with the number of failures. This runs it in a
throwaway container, prints the TAP, and fails if any test failed. It also checks that the image carries
the licence files, SOURCE.md and the tool-sources manifest the combined image is built from.

.PARAMETER Image
The image to test.

.EXAMPLE
./nano-server/nano-server-combined-tools/smoke-test.ps1 -Image windows-nano-combined-tools:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'
Write-Host "Smoke testing $Image"

# Hyper-V isolation sometimes fails to start a container in time; retry that once
for ($attempt = 1; $attempt -le 2; $attempt++) {
    $tap = docker run --rm $Image 'C:\tests\run-tests.cmd' 2>&1
    $code = $LASTEXITCODE
    if ($attempt -eq 1 -and $code -and ($tap -join "`n") -match 'hcs.*context deadline exceeded') {
        Write-Warning 'hcs timeout, retrying once'
        continue
    }
    break
}
$tap | Write-Host
if ($code) { throw "run-tests.cmd reported $code failing test(s)" }
Write-Host 'ok: every baked-in test passed'

$listing = docker run --rm --entrypoint cmd $Image /c dir /b 'C:\tools\combined' 'C:\tests' 2>&1 | Out-String
foreach ($file in 'COPYING', 'COPYING.LIB', 'WINE-COPYING.LIB', 'SOURCE.md', 'rosk32sh.dll', 'tool-sources.txt') {
    if ($listing -notmatch "(?m)^$([regex]::Escape($file))\s*$") { throw "the image is missing $file" }
}
Write-Host 'ok: the licence files, SOURCE.md, the shim and the manifest are in the image'

# Certificate support: certoc (Server Core) adds a certificate to the machine root store.
# Each docker run is a fresh container, so C:\tests\cert-check.cmd does the add and the
# registry check in the same run. ContainerUser cannot write HKLM, so run as administrator.
$store = docker run --rm --user ContainerAdministrator $Image 'C:\tests\cert-check.cmd' 2>&1 | Out-String
if ($LASTEXITCODE) { throw "certoc -addstore root check failed: $LASTEXITCODE`n$store" }
Write-Host 'ok: certoc -addstore root added the test certificate to the machine root store'
