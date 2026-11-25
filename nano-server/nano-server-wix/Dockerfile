# windows-nano-wix: WiX Toolset v5, .NET SDK, Go, and MinGit on Nano Server for building Windows MSI installers.
# Docker Hub categories: languages-and-frameworks, developer-tools
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-wix):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 --build-arg DOTNET_SDK_VERSION=10.0.404 -t windows-nano-wix:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base's -pwsh tag for WINDOWS_VERSION: PowerShell 7,
# bsdtar, jq, Microsoft Edit and the Visual C++ runtime (ADR 0017). CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022-pwsh.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}-pwsh
FROM ${BASE_IMAGE}

# .NET SDK version downloaded from builds.dotnet.microsoft.com. WiX v5 requires .NET 6 or later.
# Set with --build-arg DOTNET_SDK_VERSION=10.0.404.
ARG DOTNET_SDK_VERSION=10.0.404
# WiX Toolset version installed as a dotnet global tool. Podman's win-installer targets 5.0.2.
# Set with --build-arg WIX_VERSION=5.0.2.
ARG WIX_VERSION=5.0.2
# Go toolchain version for building Go-based projects such as Podman. GOTOOLCHAIN=local prevents
# go from downloading a different toolchain when a go.mod requests one.
# Set with --build-arg GO_VERSION=1.27.3.
ARG GO_VERSION=1.27.3

ENV \
    DOTNET_SDK_VERSION=${DOTNET_SDK_VERSION} \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_ROOT="C:\\Program Files\\dotnet" \
    WIX_VERSION=${WIX_VERSION} \
    GO_VERSION=${GO_VERSION} \
    GOTOOLCHAIN=local \
    GOROOT="C:\\Program Files\\go" \
    GOPATH="C:\\users\\containeruser\\go" \
    MINGIT_VERSION=2.56.0.4 \
    MINGIT_TAG=v2.56.0.windows.4 \
    MINGIT_DIR="C:\\Program Files\\MinGit"

# Install .NET SDK. Download to a file first; never pipe a download into an extractor on Windows
# (libarchive silently drops the first ~64 KB of a zip read from a pipe and exits 0).
RUN mkdir "%DOTNET_ROOT%" && \
    curl -fL --retry 5 --retry-delay 5 -o dotnet-sdk.zip https://builds.dotnet.microsoft.com/dotnet/Sdk/%DOTNET_SDK_VERSION%/dotnet-sdk-%DOTNET_SDK_VERSION%-win-x64.zip && \
    tar -xf dotnet-sdk.zip -C "%DOTNET_ROOT%" && \
    del dotnet-sdk.zip

# Install Go toolchain.
RUN mkdir "%GOROOT%" && \
    curl -fL --retry 5 --retry-delay 5 -o go.zip https://go.dev/dl/go%GO_VERSION%.windows-amd64.zip && \
    tar -xf go.zip -C "%ProgramFiles%" && \
    del go.zip

# Install MinGit for cloning repositories at build time.
# Do NOT install to "C:\Program Files\Git": MinGit's etc\gitconfig includes "C:/Program Files/Git/etc/gitconfig",
# which would then include itself and git fails with "exceeded maximum include depth".
RUN mkdir "%MINGIT_DIR%" && \
    curl -fL --retry 5 --retry-delay 5 -o MinGit.zip https://github.com/git-for-windows/git/releases/download/%MINGIT_TAG%/MinGit-%MINGIT_VERSION%-64-bit.zip && \
    tar -xf MinGit.zip -C "%MINGIT_DIR%" && \
    del MinGit.zip

# Create GOPATH\bin and add dotnet, Go, and MinGit to the user PATH.
# In nano 2019 we need to make the users environment key before we can add values to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN mkdir "%GOPATH%\bin" && \
    setx PATH "%DOTNET_ROOT%;%GOROOT%\bin;%GOPATH%\bin;%MINGIT_DIR%\cmd"

# Install WiX v5 as a dotnet global tool. The shim lands in %USERPROFILE%\.dotnet\tools.
# A second setx prepends the tools directory so "wix" is usable directly on PATH.
RUN dotnet tool install --global wix --version %WIX_VERSION% && \
    setx PATH "%USERPROFILE%\.dotnet\tools;%DOTNET_ROOT%;%GOROOT%\bin;%GOPATH%\bin;%MINGIT_DIR%\cmd"

WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["pwsh"]
