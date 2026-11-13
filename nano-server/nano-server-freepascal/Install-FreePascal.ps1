<#
.SYNOPSIS
Downloads Free Pascal for 64-bit Windows, lays it out under one folder, and patches it to load on Nano Server.
.DESCRIPTION
Runs in the Dockerfile's Server Core build stage, under Windows PowerShell 5.1.

The release is a tar that holds a tar of .tar.gz packages. They are unpacked and merged into the layout the
Windows compiler expects: bin\x86_64-win64 for programs and units\x86_64-win64\<package> for units.

Three things in the release can't run on Nano Server, and each is handled here:

- The assembler, linker, make and the other GNU tools are 32-bit, and Nano Server has no WoW64. They are left
  out. The compiler doesn't need them: on this target it assembles and links internally.
- Every program Free Pascal builds, the compiler included, imports kernel32's EnumResourceTypesA, which Nano
  Server's kernel32 doesn't export, so nothing starts (0xC0000139). The import comes from the fpintres unit. Its
  name is replaced, in the programs and in that unit, with EnumResourceTypesW, which Nano Server has and which
  takes the same arguments. Only the EnumResourceTypes function of the resource units ever calls it.
  Nano Server ltsc2019 also lacks EnumResourceNamesA, which the same unit imports, so there that name is replaced
  with EnumResourceNamesW in the same way.
- fppkg and fpcmkcfg import shell32's SHFileOperation, and importtl imports ole32's GetErrorInfo. Nano Server
  has neither, so those three are left out. On ltsc2019 the fp IDE is left out too: it imports user32's
  VkKeyScanExA, which only that version lacks.
.EXAMPLE
./Install-FreePascal.ps1 -Version 3.2.2 -Sha256 10D7... -Destination C:\fpc -WindowsVersion 2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    # The Nano Server version the image is for. What is missing, and so what is patched, differs for 2019.
    [Parameter(Mandatory)][ValidateSet('2019', '2022', '2025')][string]$WindowsVersion,
    # SHA-256 of the release tar. The publisher lists none, so this pins the file the image was tested with.
    [Parameter(Mandatory)][string]$Sha256,
    [Parameter(Mandatory)][string]$Destination,
    [string]$WorkFolder = 'C:\fpc-work'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$target = 'x86_64-win64'
$release = "fpc-$Version.$target"
$url = "https://downloads.freepascal.org/fpc/dist/$Version/$target/$release.tar"
# Programs that can't load on Nano Server even after the patch (see the description)
$unusable = @('fppkg.exe', 'fpcmkcfg.exe', 'importtl.exe')
# Imports Nano Server lacks, and the export with the same arguments that takes each one's place
$imports = [ordered]@{ 'EnumResourceTypesA' = 'EnumResourceTypesW' }
if ($WindowsVersion -eq '2019') {
    $unusable += 'fp.exe'
    $imports['EnumResourceNamesA'] = 'EnumResourceNamesW'
}

function Invoke-Tar {
    param([string]$Archive, [string]$Into)
    $null = New-Item -ItemType Directory -Force $Into
    tar.exe -xf $Archive -C $Into
    if ($LASTEXITCODE) { throw "tar could not unpack ${Archive}: $LASTEXITCODE" }
}

function Test-Is64Bit {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $header = [BitConverter]::ToInt32($bytes, 0x3c)
    [BitConverter]::ToUInt16($bytes, $header + 4) -eq 0x8664
}

# Replaces one name with another of the same length wherever it occurs in a file, and returns how often it did.
function Edit-ImportName {
    param([string]$Path, [string]$Old, [string]$New)
    if ($Old.Length -ne $New.Length) { throw "$New must be as long as $Old" }
    # Latin-1 maps every byte to one character and back, so the rest of the file is untouched
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString([IO.File]::ReadAllBytes($Path))
    $count = ([regex]::Matches($text, [regex]::Escape($Old))).Count
    if ($count) { [IO.File]::WriteAllBytes($Path, $latin1.GetBytes($text.Replace($Old, $New))) }
    $count
}

# Download first, check, then unpack: never pipe a download into tar
$null = New-Item -ItemType Directory -Force $WorkFolder
$archive = Join-Path $WorkFolder "$release.tar"
curl.exe -fsSLo $archive $url
if ($LASTEXITCODE) { throw "downloading $url failed: $LASTEXITCODE" }
$actual = (Get-FileHash $archive -Algorithm SHA256).Hash
if ($actual -ne $Sha256) { throw "$url has SHA-256 $actual, expected $Sha256" }

Invoke-Tar $archive $WorkFolder
$packages = Join-Path $WorkFolder 'packages'
Invoke-Tar (Join-Path $WorkFolder "$release\binary.$target.tar") $packages
$root = Join-Path $WorkFolder 'root'
foreach ($package in Get-ChildItem $packages -Filter '*.tar.gz') { Invoke-Tar $package.FullName $root }

# The packages unpack to a mix of the Windows and Unix layouts. Merge them into the Windows one.
$bin = Join-Path $Destination "bin\$target"
$units = Join-Path $Destination "units\$target"
$null = New-Item -ItemType Directory -Force $bin, $units
Copy-Item (Join-Path $root "bin\$target\*"), (Join-Path $root 'bin\*.*') $bin
Copy-Item (Join-Path $root "units\$target\*"), (Join-Path $root "lib\fpc\$Version\units\$target\*") $units -Recurse
Copy-Item (Join-Path $root 'msg') $Destination -Recurse
# The licences and the release notes
Copy-Item (Join-Path $root 'doc\fpc') (Join-Path $Destination 'doc') -Recurse

$removed = @()
foreach ($program in Get-ChildItem $bin -Filter '*.exe') {
    if ($unusable -contains $program.Name -or -not (Test-Is64Bit $program.FullName)) {
        $removed += $program.Name
        Remove-Item $program.FullName
    }
}
Remove-Item (Join-Path $bin '*.manifest')
"Left out $($removed.Count) programs Nano Server can't run: $($removed -join ', ')"

$programs = @(Get-ChildItem $bin -Filter '*.exe')
$unitFiles = @(Get-ChildItem (Join-Path $units 'rtl') -Filter '*fpintres*')
foreach ($missing in $imports.Keys) {
    $replacement = $imports[$missing]
    foreach ($program in $programs) {
        if (-not (Edit-ImportName $program.FullName $missing $replacement)) {
            throw "$($program.Name) doesn't import $missing; the release has changed, so review this script"
        }
    }
    $patched = 0
    foreach ($file in $unitFiles) { $patched += Edit-ImportName $file.FullName $missing $replacement }
    if (-not $patched) { throw "the fpintres unit doesn't import $missing; the release has changed, so review this script" }
    "Replaced $missing with $replacement in $($programs.Count) programs and $($unitFiles.Count) fpintres files"
}

# The compiler reads fpc.cfg from its own folder. fpcmkcfg, which normally writes it, can't run on Nano Server.
$config = @(
    "# Free Pascal $Version configuration, written by Install-FreePascal.ps1"
    "-Fu$Destination\units\`$fpctarget"
    "-Fu$Destination\units\`$fpctarget\*"
    "-Fu$Destination\units\`$fpctarget\rtl"
)
[IO.File]::WriteAllLines((Join-Path $bin 'fpc.cfg'), $config, [Text.Encoding]::ASCII)

Remove-Item $WorkFolder -Recurse -Force
$size = (Get-ChildItem $Destination -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
"Installed Free Pascal $Version in $Destination ({0:n0} MB)" -f $size
