<#
.SYNOPSIS
Smoke tests a built windows-servercore-vim image: vim loads with no missing DLLs, writes a file in Ex mode, reports the win32 feature, and git runs. Throws on failure.
.EXAMPLE
./server-core/server-core-vim/smoke-test.ps1 -Image windows-servercore-vim:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'
# Each test passes separate arguments to the image's "cmd /S /C" entrypoint. With the legacy passing mode, embedded
# double quotes reach cmd as \", which it doesn't understand, and vim then waits forever on the mangled command.
$PSNativeCommandArgumentPassing = 'Standard'

$tests = @(
    @{ Arguments = @('vim', '--version'); Expect = 'VIM - Vi IMproved' }
    @{ Arguments = @('vim', '-Nu', 'NONE', '-Es', '-c', "put ='hello'", '-c', 'wq t.txt', '&&', 'findstr', '/x', 'hello', 't.txt'); Expect = '(?m)^hello' }
    @{ Arguments = @('vim', '-Nu', 'NONE', '-Es', "+verbose echo has('win32')", '+q'); Expect = '1' }
    @{ Arguments = @('git', '--version'); Expect = 'git version' }
)
$failures = @()
foreach ($test in $tests) {
    $name = $test.Arguments -join ' '
    $arguments = $test.Arguments
    $out = docker run --rm --memory 2g $Image @arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host "--- $name (exit $code)"
    Write-Host $out
    # 0xC0000135 (-1073741515) is a missing DLL, and 0xC0000139 (-1073741511) a missing export
    if ($code) { $failures += "$name exited with $code" }
    elseif ($out -notmatch $test.Expect) { $failures += "$name did not print '$($test.Expect)'" }
}
if ($failures) { throw "smoke test failed: $($failures -join '; ')" }
