<#
.SYNOPSIS
    Copies the tools chosen in tool-sources.txt from the per-source folders into one output folder.

.DESCRIPTION
    Each non-comment line of -Manifest is "<tool>=<source>", where source is wine, reactos
    or servercore. The tool is copied from the matching -WineDir, -ReactosDir or
    -ServercoreDir into -OutDir. Switching a tool to another implementation is a one-line
    manifest change, as long as that source's stage fetched the tool (the wine-tools.txt
    and reactos-tools.txt candidate lists). The script fails on a duplicate tool, an
    unknown source, or a tool its source folder does not hold. When any ReactOS tool is
    chosen, rosk32sh.dll is copied too, because the patched ReactOS tools import it.

.EXAMPLE
    pwsh -NoProfile -File Select-Tools.ps1 -Manifest C:\tool-sources.txt -WineDir C:\wine-out -ReactosDir C:\ros-out -ServercoreDir C:\sc-out -OutDir C:\out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Manifest,
    [Parameter(Mandatory)] [string] $WineDir,
    [Parameter(Mandatory)] [string] $ReactosDir,
    [Parameter(Mandatory)] [string] $ServercoreDir,
    [Parameter(Mandatory)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'

$dirs = @{ wine = $WineDir; reactos = $ReactosDir; servercore = $ServercoreDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$seen = @{}
$wantShim = $false
foreach ($raw in Get-Content -LiteralPath $Manifest) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $tool, $source = $line -split '=', 2 | ForEach-Object { $_.Trim() }
    if (-not $tool -or -not $source) { throw "bad manifest line: $raw" }
    if ($tool -match '[\\/]') { throw "refusing ${tool}: not a plain file name" }
    if ($seen.ContainsKey($tool)) { throw "duplicate tool in manifest: $tool" }
    if (-not $dirs.ContainsKey($source)) { throw "unknown source '$source' for $tool (want wine, reactos or servercore)" }
    $src = Join-Path $dirs[$source] $tool
    if (-not (Test-Path -LiteralPath $src)) {
        throw "$tool is not in the $source folder ($src). Add it to that source's candidate list, or pick another source."
    }
    Copy-Item -LiteralPath $src -Destination $OutDir -Force
    $seen[$tool] = $source
    if ($source -eq 'reactos') { $wantShim = $true }
    Write-Output "$tool <- $source"
}

if ($wantShim) {
    $shim = Join-Path $ReactosDir 'rosk32sh.dll'
    if (-not (Test-Path -LiteralPath $shim)) { throw "ReactOS tools were chosen but $shim is missing" }
    Copy-Item -LiteralPath $shim -Destination $OutDir -Force
    Write-Output 'rosk32sh.dll <- reactos (shim for the patched ReactOS tools)'
}
Write-Output "Selected $($seen.Count) tool(s) into $OutDir"
