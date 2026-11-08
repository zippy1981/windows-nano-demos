<#
.SYNOPSIS
    Generates rosk32sh.def, the export definition for the ReactOS kernel32 shim.

.DESCRIPTION
    Reads the kernel32.dll imports of every PE file in -ToolsDir with Get-PeImport.ps1 and
    writes a linker definition file. Every name except __chkstk becomes a forwarder to the
    real kernel32 (for example "HeapAlloc = kernel32.HeapAlloc"); __chkstk is exported as
    the local ros_chkstk implementation from shim/chkstk.S, because Microsoft's x64
    kernel32 does not export it (it lives in ntdll). Licensed GPL-2.0-or-later as part of
    the ReactOS tools patching machinery.

.EXAMPLE
    pwsh -NoProfile -File New-ShimDef.ps1 -ToolsDir C:\ros-out -OutFile C:\shim\rosk32sh.def
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ToolsDir,
    [Parameter(Mandatory)] [string] $OutFile
)

$ErrorActionPreference = 'Stop'

$imports = & (Join-Path $PSScriptRoot 'Get-PeImport.ps1') -Path $ToolsDir
$names = @(
    foreach ($line in $imports) {
        $parts = $line -split '!', 3
        if ($parts.Count -eq 3 -and $parts[1] -ieq 'kernel32.dll' -and -not $parts[2].StartsWith('#')) { $parts[2] }
    }
)
$names = @($names | Sort-Object -Unique)
if (-not $names) { throw "No kernel32 imports found in $ToolsDir" }
if ('__chkstk' -notin $names) { Write-Warning 'No tool imports __chkstk; the shim is still generated for uniformity' }

$lines = @('LIBRARY rosk32sh.dll', 'EXPORTS') + @(
    $names | ForEach-Object {
        if ($_ -eq '__chkstk') { '    __chkstk = ros_chkstk' } else { "    $_ = kernel32.$_" }
    }
)
$parent = Split-Path -Parent $OutFile
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
Set-Content -LiteralPath $OutFile -Value $lines -Encoding ascii
Write-Output "Wrote $OutFile with $($names.Count) export(s)"
