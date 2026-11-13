<#
.SYNOPSIS
Smoke tests a built windows-servercore-neovim image: nvim loads with no missing DLLs, runs Lua headless, writes a file, and git runs. Throws on failure.
.EXAMPLE
./server-core/server-core-neovim/smoke-test.ps1 -Image windows-servercore-neovim:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'
# Each test passes separate arguments to the image's "cmd /S /C" entrypoint. With the legacy passing mode, embedded
# double quotes reach cmd as \", which it doesn't understand.
$PSNativeCommandArgumentPassing = 'Standard'

$tests = @(
    @{ Arguments = @('nvim', '--version'); Expect = 'NVIM v' }
    @{ Arguments = @('nvim', '--headless', '-c', "lua io.write('lua-ok')", '-c', 'q'); Expect = 'lua-ok' }
    @{ Arguments = @('nvim', '--clean', '--headless', '-c', "call setline(1, 'hello')", '-c', 'w t.txt', '-c', 'q', '&&', 'findstr', '/x', 'hello', 't.txt'); Expect = '(?m)^hello' }
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
    # 0xC0000135 (-1073741515) is a missing DLL, 0xC0000139 (-1073741511) a missing export, and 0xC0000142
    # (-1073741502) a DLL that failed to initialize
    if ($code) { $failures += "$name exited with $code" }
    elseif ($out -notmatch $test.Expect) { $failures += "$name did not print '$($test.Expect)'" }
}
if ($failures) { throw "smoke test failed: $($failures -join '; ')" }
