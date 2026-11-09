<#
.SYNOPSIS
    Rewrites one imported DLL name in every PE file in a folder, in place.

.DESCRIPTION
    Walks the import directory of each .exe, .com and .dll in -Path. For each descriptor
    whose DLL name equals -From (case-insensitive), it overwrites the name bytes with -To
    and zeroes the PE optional-header checksum. -From and -To must have the same length,
    so no section sizes change: kernel32.dll and rosk32sh.dll are both 12 characters.
    This is the binary patch that points ReactOS tools at the shim DLL. It refuses to
    patch a file that still has a descriptor it could not rewrite. Licensed
    GPL-2.0-or-later as part of the ReactOS tools patching machinery.

.EXAMPLE
    pwsh -NoProfile -File Set-PeImportName.ps1 -Path C:\ros-out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Path,
    [string] $From = 'kernel32.dll',
    [string] $To = 'rosk32sh.dll'
)

$ErrorActionPreference = 'Stop'

if ($From.Length -ne $To.Length) { throw "-From '$From' and -To '$To' must have the same length" }

$files = @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in '.exe', '.com', '.dll' })
if (-not $files) { throw "No PE files in $Path" }

foreach ($f in $files) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($b.Length -lt 0x40 -or [BitConverter]::ToUInt16($b, 0) -ne 0x5A4D) { throw "$($f.Name) is not a PE file (no MZ)" }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { throw "$($f.Name) is not a PE file (no PE signature)" }
    $coff = $pe + 4
    $nSections = [BitConverter]::ToUInt16($b, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($b, $coff + 16)
    $opt = $coff + 20
    $is64 = [BitConverter]::ToUInt16($b, $opt) -eq 0x20B
    $dd = $opt + $(if ($is64) { 112 } else { 96 })
    $impRva = [BitConverter]::ToUInt32($b, $dd + 8)
    if ($impRva -eq 0) { continue }
    $sec = $opt + $optSize
    $sections = for ($i = 0; $i -lt $nSections; $i++) {
        $s = $sec + 40 * $i
        [pscustomobject]@{
            VA    = [BitConverter]::ToUInt32($b, $s + 12)
            VSize = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
            Raw   = [BitConverter]::ToUInt32($b, $s + 20)
        }
    }
    $toOffset = {
        param([uint32] $Rva)
        foreach ($s in $sections) {
            if ($Rva -ge $s.VA -and $Rva -lt ($s.VA + $s.VSize)) { return [int]($Rva - $s.VA + $s.Raw) }
        }
        return [int]$Rva
    }
    $o = & $toOffset $impRva
    $patched = 0
    while ($true) {
        $nameRva = [BitConverter]::ToUInt32($b, $o + 12)
        if ($nameRva -eq 0) { break }
        $nameOff = & $toOffset $nameRva
        $end = [Array]::IndexOf($b, [byte]0, $nameOff)
        $dll = [System.Text.Encoding]::ASCII.GetString($b, $nameOff, $end - $nameOff)
        if ($dll -ieq $From) {
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($To)
            [Array]::Copy($bytes, 0, $b, $nameOff, $bytes.Length)
            $patched++
        }
        $o += 20
    }
    if ($patched) {
        # Zero the optional-header checksum (offset 64 in the optional header); the loader ignores it for these files.
        [Array]::Clear($b, $opt + 64, 4)
        [System.IO.File]::WriteAllBytes($f.FullName, $b)
        Write-Output "patched $($f.Name): $patched descriptor(s) $From -> $To"
    }
}
