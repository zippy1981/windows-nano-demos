<#
.SYNOPSIS
Long smoke test: clones Podman, builds podman.exe from source with Go, then builds the Windows MSI
with WiX v5. Downloads the matching release zip for the helper binaries (gvproxy.exe, win-sshproxy.exe)
and man pages that the MSI includes.
.DESCRIPTION
This test validates the full build chain end-to-end: Git clone, Go compilation, and WiX MSI generation.
It is intentionally slow (30-60 minutes) and is not run in the standard per-commit workflow. Run it by
hand or in a scheduled job after a successful standard build.
.PARAMETER Image
The windows-nano-wix image to test, for example windows-nano-wix:2025.
.PARAMETER PodmanVersion
Podman version to clone and build. The release zip for this version is downloaded from GitHub.
.EXAMPLE
./nano-server/nano-server-wix/smoke-test-podman.ps1 -Image windows-nano-wix:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image,
    [string]$PodmanVersion = '5.3.0'
)
$ErrorActionPreference = 'Stop'

$suffix = [guid]::NewGuid().ToString('n').Substring(0, 8)
$buildImage = "wix-smoke-podman:$suffix"

try {
    Write-Host "Building Podman $PodmanVersion MSI from $Image (this takes 30-60 minutes)"

    # Build a derived image that:
    #   1. Clones the Podman source at the pinned tag
    #   2. Downloads the same version's Windows release zip for gvproxy.exe, win-sshproxy.exe and docs
    #   3. Builds podman.exe from source (proving Go compilation works)
    #   4. Assembles the win-installer directory and runs dotnet build on wix\podman.wixproj
    #
    # __IMAGE__ and __VERSION__ are replaced by Build-Derived before passing to docker build.
    $dockerfile = @'
FROM __IMAGE__
WORKDIR C:/users/containeruser

# Clone Podman at the pinned version (shallow; we only need source, not history)
RUN git clone --depth 1 --branch v__VERSION__ https://github.com/containers/podman

# Download the Windows release zip for the same version; extract helper binaries and man pages.
# Download to a file first -- never pipe into tar on Windows (silent data loss).
RUN curl -fL --retry 5 --retry-delay 5 -o release.zip https://github.com/containers/podman/releases/download/v__VERSION__/podman-remote-release-windows_amd64.zip && tar -xf release.zip && del release.zip

# Create the directories the win-installer build expects.
RUN mkdir C:\users\containeruser\podman\contrib\win-installer\artifacts
RUN mkdir C:\users\containeruser\podman\contrib\win-installer\docs

# Copy helper binaries from the extracted release (recursive search handles varying zip layouts).
SHELL ["pwsh","-NoLogo","-NoProfile","-Command","$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';"]
RUN $f = Get-ChildItem -Recurse -Filter gvproxy.exe | Select-Object -First 1; if (-not $f) { throw 'gvproxy.exe not found in release zip' }; Copy-Item $f.FullName C:\users\containeruser\podman\contrib\win-installer\artifacts\gvproxy.exe
RUN $f = Get-ChildItem -Recurse -Filter win-sshproxy.exe | Select-Object -First 1; if (-not $f) { throw 'win-sshproxy.exe not found in release zip' }; Copy-Item $f.FullName C:\users\containeruser\podman\contrib\win-installer\artifacts\win-sshproxy.exe

# Copy man pages into docs so the HarvestDirectory has content to include in the MSI.
RUN Get-ChildItem -Recurse -Filter '*.1' | Select-Object -First 20 | ForEach-Object { Copy-Item $_.FullName C:\users\containeruser\podman\contrib\win-installer\docs\ }

# Build podman.exe from source; this is the Go compilation step that justifies the long test.
SHELL ["cmd", "/S", "/C"]
RUN cd C:\users\containeruser\podman && go build -trimpath -o C:\users\containeruser\podman\contrib\win-installer\artifacts\podman.exe .\cmd\podman\

# Build the MSI with WiX v5 via dotnet build.
# NuGet restores WixToolset.Sdk and extensions on first run; they are cached in the image layer.
RUN cd C:\users\containeruser\podman\contrib\win-installer && dotnet build wix\podman.wixproj /property:DefineConstants="VERSION=__VERSION__" /property:InstallerPlatform=x64 /property:OutputName="podman-__VERSION__"
'@

    $dockerfile.Replace('__IMAGE__', $Image).Replace('__VERSION__', $PodmanVersion) |
        docker build --memory 4g -t $buildImage -
    if ($LASTEXITCODE) { throw "Podman $PodmanVersion MSI build failed: $LASTEXITCODE" }

    # Confirm the MSI was written to the win-installer directory.
    $msiCheck = docker run --rm $buildImage "dir C:\users\containeruser\podman\contrib\win-installer\podman-$PodmanVersion.msi"
    if ($LASTEXITCODE) { throw "MSI not found after build: $msiCheck" }
    Write-Host "Podman $PodmanVersion MSI built successfully:"
    Write-Host $msiCheck
}
finally {
    docker rmi -f --no-prune $buildImage 2>$null | Out-Null
}
