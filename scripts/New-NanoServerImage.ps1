<#
.SYNOPSIS
Scaffolds a new Nano Server image folder under nano-server/.
.DESCRIPTION
Creates nano-server/nano-server-<Name>/ with a first-draft Dockerfile, build.cmd and README.md, plus
.github/workflows/<Name>-container.yml, that follow this repository's conventions: the WINDOWS_VERSION and
BASE_IMAGE build arguments, the 4 GB build memory limit, a download-to-a-file-then-extract RUN, the ContainerUser
entry point, the published image name, and a caller workflow for the shared build workflow.

The script never overwrites an existing image folder or workflow unless -Force is passed. Use -WhatIf to see what it
would write.
.PARAMETER Name
The image name in lowercase kebab-case, for example ripgrep or my-tool. The folder is nano-server/nano-server-<Name>
and the image is windows-nano-<Name>.
.PARAMETER Url
The artifact URL. The default is a placeholder. When -VersionString is supplied, the version substring in this URL is
replaced with a Docker build-argument reference.
.PARAMETER ExtractionTool
The executable that extracts the artifact. Defaults to tar.exe. For a Deflate64 ZIP that tar.exe cannot read, use
7z.exe; the script knows 7-Zip's arguments, or pass them with -ExtractionArguments.
.PARAMETER ExtractionArguments
The arguments for the extraction tool. Use {archive} and {destination} as placeholders. The defaults are tar's
-xf {archive} -C "{destination}" and 7-Zip's x {archive} -o"{destination}" -y.
.PARAMETER VersionString
The exact version substring in Url to turn into a build argument. For example, 1.2.3 in
https://example.com/v1.2.3/tool.zip becomes %MY_TOOL_VERSION%, with ARG MY_TOOL_VERSION=1.2.3.
.PARAMETER Force
Overwrite an existing nano-server-<Name> folder and its generated files. Without it, the script throws.
.PARAMETER RepositoryRoot
The repository root. Defaults to the parent of this script's folder.
.EXAMPLE
./scripts/New-NanoServerImage.ps1 -Name ripgrep `
    -Url https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip `
    -VersionString 14.1.1
.EXAMPLE
./scripts/New-NanoServerImage.ps1 -Name tool -Url https://example.com/tool-1.2.3.zip -VersionString 1.2.3 `
    -ExtractionTool 7z.exe
.EXAMPLE
./scripts/New-NanoServerImage.ps1 -Name tool -Url https://example.com/tool.zip -WhatIf
#>
#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Name,

    [ValidateScript({ [uri]::IsWellFormedUriString($_, [System.UriKind]::Absolute) })]
    [string]$Url = 'https://example.com/download/artifact.zip',

    [ValidateNotNullOrEmpty()]
    [string]$ExtractionTool = 'tar.exe',

    [string]$ExtractionArguments,

    [ValidateNotNullOrEmpty()]
    [string]$VersionString,

    [switch]$Force,

    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    throw "Name '$Name' is not lowercase kebab-case. Use letters, digits and single hyphens, for example my-tool."
}

if ($VersionString -and -not $Url.Contains($VersionString)) {
    throw "VersionString '$VersionString' is not in Url '$Url'. Pass the exact version substring that appears in the URL."
}


if (-not $ExtractionArguments) {
    $ExtractionArguments = if ($ExtractionTool -match '(?i)(^|\\)7z(\.exe)?$') {
        'x {archive} -o"{destination}" -y'
    } else {
        '-xf {archive} -C "{destination}"'
    }
}

$versionVariable = if ($VersionString) {
    ($Name -replace '-', '_').ToUpperInvariant() + '_VERSION'
}

$installDirectory = "C:\Program Files\$Name"
$installEnvironment = ($Name -replace '-', '_').ToUpperInvariant() + '_DIR'
$imageName = "windows-nano-$Name"
$folderName = "nano-server-$Name"
$imageContext = "nano-server/$folderName"
$imageDirectory = Join-Path $RepositoryRoot (Join-Path 'nano-server' $folderName)
$workflowName = "$Name-container.yml"
$workflowPath = Join-Path $RepositoryRoot (Join-Path '.github/workflows' $workflowName)
$workflowDisplayName = ($Name -split '-' | ForEach-Object {
    $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
}) -join ' '
$archiveName = [System.IO.Path]::GetFileName(([uri]$Url).AbsolutePath)
if (-not $archiveName -or $archiveName -eq '/') { $archiveName = 'artifact.zip' }

$urlWithVersion = $Url
if ($VersionString) { $urlWithVersion = $Url.Replace($VersionString, "%$versionVariable%") }

$versionArgument = ''
$versionEnvironment = ''
if ($VersionString) {
    $versionArgument = @"
# The $Name version in the download URL. Set with --build-arg $versionVariable=<version>.
ARG $versionVariable=$VersionString
"@
    $versionEnvironment = @"
# Record the installed version for consumers of the image.
ENV $versionVariable=`${$versionVariable}
"@
}

$dockerfileTemplate = @'
# __IMAGE_NAME__: __NAME__ on Nano Server.
# Docker Hub categories: developer-tools
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/__IMAGE_NAME__):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t __IMAGE_NAME__:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base for WINDOWS_VERSION (ADR 0017); CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}
FROM ${BASE_IMAGE}

__VERSION_ARGUMENT__

# Where the artifact is installed and the environment variable that points at it.
ENV __INSTALL_ENVIRONMENT__="__INSTALL_DIRECTORY__"

# Download the artifact to a file, then extract it under the install folder.
# Downloading first matters: piping an archive into the extractor can silently skip entries.
__EXTRACTION_NOTE__
# If the artifact publisher provides a SHA-256, pin it as a build argument and check it here before extraction.
RUN mkdir "%__INSTALL_ENVIRONMENT__%" && \
    curl -fLo "C:\__ARCHIVE_NAME__" "__URL__" && \
    __EXTRACTION_TOOL__ __EXTRACTION_ARGUMENTS__ && \
    del "C:\__ARCHIVE_NAME__"

# Add the install folder to the user PATH. Nano Server 2019 needs the HKCU\Environment key
# to exist before setx can write to it; 2022 and later create it on demand.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "%__INSTALL_ENVIRONMENT__%"

__VERSION_ENVIRONMENT__

# The container has two users, ContainerAdministrator and ContainerUser.
# They don't show up in the Net User command, but they have profile directories with registry hives.
WORKDIR C:/users/containeruser

# Set the entry point and default command
ENTRYPOINT ["cmd", "/S", "/C"]
'@

$resolvedExtractionArguments = $ExtractionArguments.
    Replace('{archive}', ('C:\' + $archiveName)).
    Replace('{destination}', ('%' + $installEnvironment + '%'))

$extractionNote = if ($ExtractionTool -match '(?i)(^|\\)7z(\.exe)?$') {
    '# 7z.exe is not part of Nano Server; add an install step before this RUN if the base image lacks it.'
} elseif ($ExtractionTool -match '(?i)(^|\\)tar(\.exe)?$') {
    '# tar.exe is part of Nano Server and needs no extra install.'
} else {
    "# $ExtractionTool must be on PATH; add an install step before this RUN if the base image lacks it."
}

$extractionReadme = if ($ExtractionTool -match '(?i)(^|\\)7z(\.exe)?$') {
    '7-Zip is not part of Nano Server; add an install step before the extraction RUN.'
} elseif ($ExtractionTool -match '(?i)(^|\\)tar(\.exe)?$') {
    'tar.exe is part of Nano Server.'
} else {
    "$ExtractionTool must be in the image; add an install step if it is not."
}

$dockerfile = $dockerfileTemplate.
    Replace('__IMAGE_NAME__', $imageName).
    Replace('__NAME__', $Name).
    Replace('__VERSION_ARGUMENT__', $versionArgument.TrimEnd()).
    Replace('__VERSION_ENVIRONMENT__', $versionEnvironment.TrimEnd()).
    Replace('__INSTALL_ENVIRONMENT__', $installEnvironment).
    Replace('__INSTALL_DIRECTORY__', $installDirectory.Replace('\', '\\')).
    Replace('__ARCHIVE_NAME__', $archiveName).
    Replace('__URL__', $urlWithVersion).
    Replace('__EXTRACTION_TOOL__', $ExtractionTool).
    Replace('__EXTRACTION_NOTE__', $extractionNote).
    Replace('__EXTRACTION_ARGUMENTS__', $resolvedExtractionArguments)


$versionBuildLines = ''
$versionTags = ''
$versionReadme = 'The Dockerfile has no version build argument; add one if the artifact URL changes between releases.'
if ($VersionString) {
    $versionBuildLines = @"

rem $versionVariable is optional. Unset builds the Dockerfile's default.
if not defined $versionVariable set "$versionVariable=$VersionString"
set "BUILD_ARGS=%BUILD_ARGS% --build-arg $versionVariable=%$versionVariable%"
"@
    $versionTags = " -t windows-nano-${Name}:%$versionVariable%-%WINDOWS_VERSION% -t zippy1981/windows-nano-${Name}:%$versionVariable%-%WINDOWS_VERSION%"
    $versionReadme = "Set ``$versionVariable`` to override the version (default ``$VersionString``)."
}

$buildCommandTemplate = @'
@echo off
setlocal
rem Scaffolded by scripts/New-NanoServerImage.ps1. Adjust the build steps to match the artifact.
rem Copy any host DLLs the image needs into .\system32 here.
if not defined WINDOWS_VERSION set "WINDOWS_VERSION=2025"
set "BUILD_ARGS=--build-arg WINDOWS_VERSION=%WINDOWS_VERSION%"
if defined BASE_IMAGE set "BUILD_ARGS=%BUILD_ARGS% --build-arg BASE_IMAGE=%BASE_IMAGE%"
__VERSION_BUILD_LINES__
set "TAGS=-t windows-nano-__NAME__:%WINDOWS_VERSION% -t zippy1981/windows-nano-__NAME__:%WINDOWS_VERSION%__VERSION_TAGS__"
docker build --memory 4g %BUILD_ARGS% %TAGS% "%~dp0."
'@

$buildCommand = $buildCommandTemplate.
    Replace('__VERSION_BUILD_LINES__', $versionBuildLines.Trim()).
    Replace('__VERSION_TAGS__', $versionTags).
    Replace('__NAME__', $Name)

$readmeTemplate = @'
# __IMAGE_NAME__

Scaffolded by `scripts/New-NanoServerImage.ps1`. Review the generated Dockerfile and replace the description below.

## What it is

A Nano Server image that installs __NAME__ from <__URL__>.

## Build

```cmd
build.cmd
```

Set `WINDOWS_VERSION` to 2019, 2022 or 2025, and `BASE_IMAGE` to override the base image. __VERSION_README__

## What is installed

- The artifact is downloaded to a file and extracted to `__INSTALL_DIRECTORY__` with `__EXTRACTION_TOOL__`. __EXTRACTION_README__
- `__INSTALL_ENVIRONMENT__` points at the install folder, which is on the user `PATH`.

## Before publishing

- [ ] Add `smoke-test.ps1` next to the Dockerfile.
- [ ] Review the generated `.github/workflows/__WORKFLOW__` caller workflow.
- [ ] Add the image to the root README image list.
- [ ] Run `uv run pytest` and `uv run pre-commit run --all-files`.
'@

$readme = $readmeTemplate.
    Replace('__IMAGE_NAME__', $imageName).
    Replace('__NAME__', $Name).
    Replace('__URL__', $Url).
    Replace('__VERSION_README__', $versionReadme).
    Replace('__INSTALL_DIRECTORY__', $installDirectory).
    Replace('__INSTALL_ENVIRONMENT__', $installEnvironment).
    Replace('__EXTRACTION_TOOL__', $ExtractionTool).
    Replace('__EXTRACTION_README__', $extractionReadme).
    Replace('__WORKFLOW__', $workflowName)

$workflowTemplate = @'
# Builds and tests __IMAGE_NAME__ for every Windows version through the shared workflow (ADR 0009)
name: __DISPLAY_NAME__ container

on:
  push:
    branches: [main]
    paths:
      - '__CONTEXT__/**'
      - '.github/workflows/__WORKFLOW__'
      - '.github/workflows/build-windows-image.yml'
  pull_request:
    branches: [main]
    paths:
      - '__CONTEXT__/**'
      - '.github/workflows/__WORKFLOW__'
      - '.github/workflows/build-windows-image.yml'
  workflow_dispatch:

# A new push to a pull request cancels that pull request's older runs. Pushes to main always run to completion.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  build:
    uses: ./.github/workflows/build-windows-image.yml
    with:
      context: __CONTEXT__
      image: __IMAGE_NAME__
'@

$workflow = $workflowTemplate.
    Replace('__IMAGE_NAME__', $imageName).
    Replace('__DISPLAY_NAME__', $workflowDisplayName).
    Replace('__CONTEXT__', $imageContext).
    Replace('__WORKFLOW__', $workflowName)

$files = @(
    [pscustomobject]@{ Path = (Join-Path $imageDirectory 'Dockerfile'); Content = $dockerfile; EndOfLine = "`n" }
    [pscustomobject]@{ Path = (Join-Path $imageDirectory 'build.cmd'); Content = $buildCommand; EndOfLine = "`r`n" }
    [pscustomobject]@{ Path = (Join-Path $imageDirectory 'README.md'); Content = $readme; EndOfLine = "`n" }
    [pscustomobject]@{ Path = $workflowPath; Content = $workflow; EndOfLine = "`n" }
)

if ((Test-Path -LiteralPath $imageDirectory) -and -not $Force) {
    throw "Image folder '$imageDirectory' already exists. Pass -Force to overwrite the generated files."
}

foreach ($file in $files) {
    if ((Test-Path -LiteralPath $file.Path) -and -not $Force) {
        throw "File '$($file.Path)' already exists. Pass -Force to overwrite it."
    }
}

if ($PSCmdlet.ShouldProcess("$imageDirectory and $workflowPath", 'Create Nano Server image scaffold')) {
    foreach ($file in $files) {
        $parent = Split-Path -Parent $file.Path
        if (-not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }

        $content = $file.Content.Replace("`r`n", "`n")
        if ($file.EndOfLine -eq "`r`n") {
            $content = $content.Replace("`n", "`r`n")
        }
        $content = $content.TrimEnd([char[]]"`r`n") + $file.EndOfLine

        [System.IO.File]::WriteAllText($file.Path, $content, [System.Text.UTF8Encoding]::new($false))
    }
}

[pscustomobject]@{
    Name = $Name
    Image = $imageName
    Folder = $imageDirectory
    Dockerfile = (Join-Path $imageDirectory 'Dockerfile')
    BuildScript = (Join-Path $imageDirectory 'build.cmd')
    Readme = (Join-Path $imageDirectory 'README.md')
    Workflow = $workflowPath
    VersionVariable = $versionVariable
    ExtractionTool = $ExtractionTool
}
