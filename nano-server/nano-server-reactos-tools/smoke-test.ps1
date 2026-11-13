<#
.SYNOPSIS
Smoke tests a built windows-nano-reactos-tools image: runs the baked-in tests, checks the licence files.

.DESCRIPTION
C:\tests\run-tests.cmd in the image writes TAP and exits with the number of failures. This runs it in a
throwaway container, prints the TAP, and fails if any test failed. It also checks that the image carries
the licence files and SOURCE.md, which the GPL requires to go with the binaries.

.PARAMETER Image
The image to test.

.EXAMPLE
./nano-server/nano-server-reactos-tools/smoke-test.ps1 -Image windows-nano-reactos-tools:2025
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

$listing = docker run --rm --entrypoint cmd $Image /c dir /b 'C:\tools\reactos' 2>&1 | Out-String
foreach ($file in 'COPYING', 'COPYING.LIB', 'SOURCE.md', 'rosk32sh.dll') {
    if ($listing -notmatch "(?m)^$([regex]::Escape($file))\s*$") { throw "the image is missing $file" }
}
Write-Host 'ok: the licence files, SOURCE.md and the shim are in the image'
