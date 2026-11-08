<#
.SYNOPSIS
    Lists the imports of PE files as file!dll!name lines.

.DESCRIPTION
    Parses the PE32+ import directory of every .exe, .com and .dll in -Path (or the single
    file given with -File) and writes one "file!dll!name" line per imported name. Ordinal
    imports are written as #<ordinal>. New-ShimDef.ps1 consumes this output to generate the
    kernel32 forwarder definition for rosk32sh.dll. Pure .NET, so it runs in pwsh 7 and in
    Windows PowerShell 5.1 on Server Core.

.EXAMPLE
    pwsh -NoProfile -File Get-PeImport.ps1 -Path C:\ros-out
#>
[CmdletBinding()]
param(
    [string] $Path,
    [string] $File
)

$ErrorActionPreference = 'Stop'

function Read-PeHeader {
    param([string] $PeFile)
    $b = [System.IO.File]::ReadAllBytes($PeFile)
    if ($b.Length -lt 0x40 -or [BitConverter]::ToUInt16($b, 0) -ne 0x5A4D) { throw "$PeFile is not a PE file (no MZ)" }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { throw "$PeFile is not a PE file (no PE signature)" }
    $coff = $pe + 4
    $nSections = [BitConverter]::ToUInt16($b, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($b, $coff + 16)
    $opt = $coff + 20
    $is64 = [BitConverter]::ToUInt16($b, $opt) -eq 0x20B
    $dd = $opt + $(if ($is64) { 112 } else { 96 })
    $dirs = for ($i = 0; $i -lt 16; $i++) {
        [pscustomobject]@{ Rva = [BitConverter]::ToUInt32($b, $dd + 8 * $i); Size = [BitConverter]::ToUInt32($b, $dd + 8 * $i + 4) }
    }
    $sec = $opt + $optSize
    $sections = for ($i = 0; $i -lt $nSections; $i++) {
        $s = $sec + 40 * $i
        [pscustomobject]@{
            VA    = [BitConverter]::ToUInt32($b, $s + 12)
            VSize = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
            Raw   = [BitConverter]::ToUInt32($b, $s + 20)
        }
    }
    [pscustomobject]@{ Bytes = $b; Is64 = $is64; Dirs = $dirs; Sections = $sections }
}

function Get-PeOffset {
    param($Pe, [uint32] $Rva)
    foreach ($s in $Pe.Sections) {
        if ($Rva -ge $s.VA -and $Rva -lt ($s.VA + $s.VSize)) { return [int]($Rva - $s.VA + $s.Raw) }
    }
    return [int]$Rva
}

function Get-PeCString {
    param($Pe, [uint32] $Rva)
    $o = Get-PeOffset $Pe $Rva
    $e = [Array]::IndexOf($Pe.Bytes, [byte]0, $o)
    [System.Text.Encoding]::ASCII.GetString($Pe.Bytes, $o, $e - $o)
}

function Get-PeImport {
    param([string] $PeFile)
    $pe = Read-PeHeader $PeFile
    $b = $pe.Bytes
    $imp = $pe.Dirs[1]
    if ($imp.Rva -eq 0) { return }
    $o = Get-PeOffset $pe $imp.Rva
    while ($true) {
        $ilt = [BitConverter]::ToUInt32($b, $o); $nameRva = [BitConverter]::ToUInt32($b, $o + 12); $iat = [BitConverter]::ToUInt32($b, $o + 16)
        if ($nameRva -eq 0) { break }
        $dll = Get-PeCString $pe $nameRva
        $table = if ($ilt -ne 0) { $ilt } else { $iat }
        $t = Get-PeOffset $pe $table
        $step = if ($pe.Is64) { 8 } else { 4 }
        while ($true) {
            if ($pe.Is64) {
                $v = [BitConverter]::ToUInt64($b, $t)
                if ($v -eq 0) { break }
                $byOrdinal = ($v -band 0x8000000000000000) -ne 0
                $name = if ($byOrdinal) { "#$($v -band 0xFFFF)" } else { Get-PeCString $pe ([uint32](($v -band 0x7FFFFFFF) + 2)) }
            } else {
                $v = [uint64][BitConverter]::ToUInt32($b, $t)
                if ($v -eq 0) { break }
                $byOrdinal = ($v -band 0x80000000) -ne 0
                $name = if ($byOrdinal) { "#$($v -band 0xFFFF)" } else { Get-PeCString $pe ([uint32](($v -band 0x7FFFFFFF) + 2)) }
            }
            [pscustomobject]@{ Dll = $dll; Name = $name }
            $t += $step
        }
        $o += 20
    }
}

$files = @()
if ($File) {
    $files = @(Get-Item -LiteralPath $File)
} elseif ($Path) {
    $files = @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in '.exe', '.com', '.dll' })
} else {
    throw 'Give -Path or -File'
}
if (-not $files) { throw 'No PE files found' }

foreach ($f in $files) {
    foreach ($imp in Get-PeImport $f.FullName) {
        Write-Output "$($f.Name)!$($imp.Dll)!$($imp.Name)"
    }
}
