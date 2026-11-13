<#
.SYNOPSIS
Smoke tests a built windows-nano-freepascal image: compiles and runs the two example programs, and checks that the tools left in the image start. Throws on failure.
.EXAMPLE
./nano-server/nano-server-freepascal/smoke-test.ps1 -Image windows-nano-freepascal:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

function Invoke-InImage([string]$Command, [string]$What) {
    $out = docker run --rm $Image $Command
    $code = $LASTEXITCODE
    $out | Write-Host
    if ($code) { throw "${What} failed: $code" }
    $out -join "`n"
}

# The compiler starts at all only because of the import patch (Install-FreePascal.ps1)
$version = Invoke-InImage 'fpc -iV && echo target && fpc -iTP && fpc -iTO && echo recorded %FREEPASCAL_VERSION%' 'fpc -iV'
if ($version -notmatch '(?s)^(\d+\.\d+\.\d+)\s+target\s+x86_64\s+win64\s+recorded \1\s*$') { throw "unexpected compiler identity: $version" }

# A program with no units of its own, then one that needs units from three packages
$hello = Invoke-InImage 'fpc -FE. C:\fpc\examples\hello.pas && hello.exe' 'compiling hello.pas'
if ($hello -notmatch 'Hello from Free Pascal \d+\.\d+\.\d+ on Win64/x86_64') { throw 'hello.exe did not print its greeting' }
$inventory = Invoke-InImage 'fpc -FE. C:\fpc\examples\inventory.pas && inventory.exe' 'compiling inventory.pas'
if ($inventory -notmatch '\{ "gears" : 30, "widgets" : 12, "total" : 42, "duplicate" : "EListError" \}') {
    throw 'inventory.exe did not print the expected JSON'
}

# The other tools start. Each prints its banner or usage; a tool that can't load exits with 0xC0000139 or 0xC0000135.
$tools = 'fpcres -V', 'instantfpc -v', 'ppudump -V', 'fpcmake -v', 'pas2js -iV', 'fpdoc --help', 'h2pas', 'delp -h', 'ptop -h', 'bin2obj'
foreach ($tool in $tools) {
    $out = docker run --rm $Image "$tool 2>&1"
    $code = $LASTEXITCODE
    "$tool -> exit $code, $(@($out)[0])" | Write-Host
    if ($code -lt 0 -or $code -gt 255 -or -not $out) { throw "$tool did not start: $code" }
}

# Nothing 32-bit and none of the three tools that can't load were left behind
$leftovers = docker run --rm $Image 'for %f in (ld as make strip windres fppkg fpcmkcfg importtl) do @if exist C:\fpc\bin\x86_64-win64\%f.exe echo %f'
if ($leftovers) { throw "these programs can't run on Nano Server and should have been left out: $leftovers" }
'smoke test passed' | Write-Host
