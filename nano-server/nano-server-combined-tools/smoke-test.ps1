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

$listing = docker run --rm --entrypoint cmd $Image /c dir /b 'C:\Program Files\combined-tools' 'C:\tests' 2>&1 | Out-String
foreach ($file in 'COPYING', 'COPYING.LIB', 'WINE-COPYING.LIB', 'SOURCE.md', 'rosk32sh.dll', 'tool-sources.txt') {
    if ($listing -notmatch "(?m)^$([regex]::Escape($file))\s*$") { throw "the image is missing $file" }
}
Write-Host 'ok: the licence files, SOURCE.md, the shim and the manifest are in the image'

# Certificate support: certoc (Server Core) adds a certificate to the machine root store.
# ContainerUser cannot write HKLM, so run this check as ContainerAdministrator. The fixture
# certificate's SHA-1 thumbprint is baked into the registry key name it creates.
$thumbprint = '19E13843A8BF4B194E8E17F89DDBF7096E0D5BA7'
$add = docker run --rm --user ContainerAdministrator --entrypoint 'C:\Program Files\combined-tools\certoc.exe' $Image -addstore root 'C:\tests\fixtures\test.cer' 2>&1
if ($LASTEXITCODE) { throw "certoc -addstore root failed: $LASTEXITCODE`n$add" }
$keys = docker run --rm --user ContainerAdministrator --entrypoint 'C:\Windows\System32\reg.exe' $Image query 'HKLM\SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates' 2>&1 | Out-String
if ($LASTEXITCODE) { throw "reg query of the root store failed: $LASTEXITCODE" }
if ($keys -notmatch $thumbprint) { throw "the test certificate ($thumbprint) is not in the root store: $keys" }
Write-Host 'ok: certoc -addstore root added the test certificate to the machine root store'
