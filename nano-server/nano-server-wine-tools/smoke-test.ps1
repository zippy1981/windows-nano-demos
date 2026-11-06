<#
.SYNOPSIS
Smoke tests a built windows-nano-wine-tools image: runs the baked-in tests, checks the source tarball is there.
.DESCRIPTION
C:\tests\run-tests.cmd in the image writes TAP and exits with the number of failures. This runs it in a throwaway
container, prints the TAP, and fails if any test failed. It also checks that the image carries the Wine source
tarball, its signature and the licence files, which the LGPL requires to go with the binaries.
.PARAMETER Image
The image to test.
.EXAMPLE
./nano-server/nano-server-wine-tools/smoke-test.ps1 -Image windows-nano-wine-tools:2025
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

# Each path is its own argument to cmd: quotes inside one string don't survive docker and the cmd /S /C entrypoint
$listing = docker run --rm --entrypoint cmd $Image /c dir /b 'C:\Program Files\wine-tools' 'C:\Program Files\wine-tools\source' 2>&1 |
    Out-String
foreach ($file in 'COPYING.LIB', 'LICENSE', 'AUTHORS', 'SOURCE.md', 'wine-11.0.tar.xz', 'wine-11.0.tar.xz.sign') {
    if ($listing -notmatch "(?m)^$([regex]::Escape($file))\s*$") { throw "the image is missing $file, which the LGPL requires with the binaries" }
}
Write-Host 'ok: the licence files and the Wine 11.0 source tarball are in the image'
