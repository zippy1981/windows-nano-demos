# windows-nano-freepascal: Free Pascal compiler for 64-bit Windows on Nano Server, patched so it and its programs start there.
# Docker Hub categories: languages-and-frameworks, developer-tools
#
# Compile and run an example:
#   docker run --rm windows-nano-freepascal:2025 "fpc -FE. C:\fpc\examples\hello.pas && hello.exe"
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-freepascal):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-freepascal:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base for WINDOWS_VERSION (ADR 0017); CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}
# The Free Pascal release to install. Set with --build-arg FREEPASCAL_VERSION=<version>, together with FREEPASCAL_SHA256.
ARG FREEPASCAL_VERSION=3.2.2

# The release is downloaded, checked, unpacked and patched in a throwaway Server Core stage, which has PowerShell.
# Install-FreePascal.ps1 says what is patched and why.
FROM mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64 AS build
SHELL ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop';"]

ARG WINDOWS_VERSION
ARG FREEPASCAL_VERSION
# SHA-256 of fpc-<version>.x86_64-win64.tar. freepascal.org publishes no checksum, so this pins the file the image was
# tested with. Set with --build-arg FREEPASCAL_SHA256=<hash> whenever FREEPASCAL_VERSION changes.
ARG FREEPASCAL_SHA256=10D776CF6E86DCCAB482B81285DA58A9CC8E0AA9C0558B78D3BF08D3981B4924

COPY Install-FreePascal.ps1 C:/build/Install-FreePascal.ps1
RUN C:\build\Install-FreePascal.ps1 -Version $env:FREEPASCAL_VERSION -Sha256 $env:FREEPASCAL_SHA256 -Destination C:\fpc -WindowsVersion $env:WINDOWS_VERSION

FROM ${BASE_IMAGE}

COPY --from=build C:/fpc C:/fpc
COPY examples C:/fpc/examples

# FPCDIR is where Free Pascal's own tools look for the installation.
ENV FPCDIR="C:\\fpc"

# Add the compiler's folder to the user PATH. Nano Server 2019 needs the HKCU\Environment key
# to exist before setx can write to it; 2022 and later create it on demand.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "%FPCDIR%\bin\x86_64-win64"

# Record the installed version for consumers of the image.
ARG FREEPASCAL_VERSION
ENV FREEPASCAL_VERSION=${FREEPASCAL_VERSION}

# The container has two users, ContainerAdministrator and ContainerUser.
# They don't show up in the Net User command, but they have profile directories with registry hives.
WORKDIR C:/users/containeruser

# Set the entry point and default command
ENTRYPOINT ["cmd", "/S", "/C"]
