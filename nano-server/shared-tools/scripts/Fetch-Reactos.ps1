<#
.SYNOPSIS
    Downloads the pinned ReactOS nightly, extracts the listed tools, builds the shim and patches them.

.DESCRIPTION
    Runs in the Dockerfile's Server Core fetch stage with Windows PowerShell. Downloads
    7-Zip (pinned by SHA-256) and the pinned ReactOS x64 MSVC nightly boot CD for -ReactosVersion
    (pinned by SHA-256), extracts only the files listed in -ToolsFile from reactos\system32, builds
    rosk32sh.dll with llvm-mingw (pinned by SHA-256) from shim\chkstk.S and the generated
    forwarder definition, and rewrites each tool's kernel32.dll import to rosk32sh.dll
    with Set-PeImportName.ps1. The patched tools and the shim land in -OutDir.

.EXAMPLE
    powershell -NoProfile -File Fetch-Reactos.ps1 -ReactosVersion 4.17 -ToolsFile C:\fetch\tools.txt -OutDir C:\ros-out -ContextDir C:\fetch
#>
[CmdletBinding()]
param(
    [string] $ReactosVersion = '4.17',
    [Parameter(Mandatory)] [string] $ToolsFile,
    [Parameter(Mandatory)] [string] $OutDir,
    [Parameter(Mandatory)] [string] $ContextDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# The ReactOS x64 MSVC nightly boot CD pinned for each release line. Add a line when the release changes.
$rosBuilds = @{
    '4.17' = @{
        Build = '0.4.17-dev-1340-gfaa2d03'
        Sha256 = '37f8642188a949a109000c96522407ce7b515658b804569f717ac95e7051193b'
        Commit = 'faa2d0325a880c8ef56bad1e52e7288176ef9975'
    }
}
if (-not $rosBuilds.ContainsKey($ReactosVersion)) { throw "no pinned ReactOS nightly for version $ReactosVersion" }
$rosBuild = $rosBuilds[$ReactosVersion]
Write-Host "ReactOS ${ReactosVersion}: nightly $($rosBuild.Build), source commit $($rosBuild.Commit)"
$rosFile = "reactos-bootcd-$($rosBuild.Build)-x64-msvc-win-dbg.7z"
$rosUrl = "https://iso.reactos.org/bootcd/$rosFile"
$rosSha256 = $rosBuild.Sha256
$sevenZrUrl = 'https://www.7-zip.org/a/7zr.exe'
$sevenZrSha256 = '256feca8e274e5da655e2a284fabafd9f554365eb164862089dacd4e8276d282'
$sevenZipUrl = 'https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe'
$sevenZipSha256 = 'fd99e86f57d8f429ef5ed045bf98315af962e2309b0f1ba87a147a44c71647d0'
$llvmUrl = 'https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/llvm-mingw-20261020-ucrt-x86_64.zip'
$llvmSha256 = 'fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd'

function Get-PinnedFile {
    param([string] $Url, [string] $Destination, [string] $Sha256)
    & curl.exe -fsSL --retry 5 --retry-delay 5 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed ($LASTEXITCODE): $Url" }
    $hash = (Get-FileHash -Algorithm SHA256 $Destination).Hash.ToLowerInvariant()
    if ($hash -ne $Sha256) { throw "SHA-256 mismatch for $Url`: got $hash, expected $Sha256" }
}

$tools = Get-Content -LiteralPath $ToolsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($t in $tools) {
    if ($t -match '[\\/]') { throw "refusing ${t}: not a plain file name" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("reactos-fetch-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $sevenZr = Join-Path $work '7zr.exe'
    Get-PinnedFile $sevenZrUrl $sevenZr $sevenZrSha256
    $sevenZipExe = Join-Path $work '7z-x64.exe'
    Get-PinnedFile $sevenZipUrl $sevenZipExe $sevenZipSha256
    $sevenDir = Join-Path $work '7z'
    & $sevenZr x -y "-o$sevenDir" $sevenZipExe | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7zr could not unpack 7-Zip ($LASTEXITCODE)" }
    $seven = Join-Path $sevenDir '7z.exe'
    if (-not (Test-Path -LiteralPath $seven)) { throw "7z.exe not found after unpacking to $sevenDir" }

    $rosArchive = Join-Path $work $rosFile
    Get-PinnedFile $rosUrl $rosArchive $rosSha256
    & $seven x -y "-o$work" $rosArchive | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z could not unpack the ReactOS boot CD ($LASTEXITCODE)" }
    $iso = Get-ChildItem -LiteralPath $work -Filter '*.iso' | Select-Object -First 1
    if (-not $iso) { throw 'No .iso inside the ReactOS boot CD archive' }
    $rosDir = Join-Path $work 'ros'
    & $seven x -y "-o$rosDir" $iso.FullName 'reactos\system32\*' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z could not unpack the ReactOS ISO ($LASTEXITCODE)" }
    $system32 = Join-Path $rosDir 'reactos\system32'
    if (-not (Test-Path -LiteralPath $system32)) { $system32 = Join-Path $rosDir 'reactos/system32' }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    foreach ($t in $tools) {
        $src = Join-Path $system32 $t
        if (-not (Test-Path -LiteralPath $src)) { throw "missing $t in ReactOS system32" }
        Copy-Item -LiteralPath $src -Destination $OutDir -Force
    }

    $llvmZip = Join-Path $work 'llvm-mingw.zip'
    Get-PinnedFile $llvmUrl $llvmZip $llvmSha256
    $llvmDir = Join-Path $work 'llvm'
    & $seven x -y "-o$llvmDir" $llvmZip | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z could not unpack llvm-mingw ($LASTEXITCODE)" }
    $clang = Get-ChildItem -LiteralPath $llvmDir -Recurse -Filter 'x86_64-w64-mingw32-clang.exe' | Select-Object -First 1
    if (-not $clang) { throw 'x86_64-w64-mingw32-clang.exe not found in llvm-mingw' }

    $def = Join-Path $work 'rosk32sh.def'
    & (Join-Path $PSScriptRoot 'New-ShimDef.ps1') -ToolsDir $OutDir -OutFile $def
    $shimAsm = Join-Path $ContextDir 'shim\chkstk.S'
    $shimDll = Join-Path $OutDir 'rosk32sh.dll'
    & $clang.FullName -shared -nostdlib '-Wl,--entry,DllMain' $shimAsm $def -o $shimDll
    if ($LASTEXITCODE -ne 0) { throw "clang could not build rosk32sh.dll ($LASTEXITCODE)" }

    & (Join-Path $PSScriptRoot 'Set-PeImportName.ps1') -Path $OutDir
    Get-ChildItem -LiteralPath $OutDir | Format-Table Name, Length -AutoSize
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
