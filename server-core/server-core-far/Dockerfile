# windows-servercore-far: Far Manager 3 (x64) on Server Core. Run it with docker run -it.
# Docker Hub categories: developer-tools
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-servercore-far):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-servercore-far:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. CI pins it to a digest.
# Far needs Server Core on ltsc2019 and ltsc2022. Far.exe statically imports desktop Win32 DLLs, and on
# nanoserver-base:ltsc2019 and ltsc2022 it exits with 0xC0000135 (STATUS_DLL_NOT_FOUND) before printing anything.
# Of its direct imports, netapi32.dll is the one ltsc2025 has and they don't. Copying DLLs over from Server Core
# only changes the error to 0xC0000139 (STATUS_ENTRYPOINT_NOT_FOUND). On ltsc2025 Far runs on nanoserver-base (#85).
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64

# Download Far, check its SHA-256 and unpack it in one nanoserver-base stage. The -pwsh tag has PowerShell for
# Get-FileHash (Nano Server has no certutil; the shell is pwsh, not powershell), and tar is the base's bsdtar 3.8.11: C:\tools\bin comes first on PATH
# and holds bsdtar as tar.exe, ahead of System32's tar.exe. Far ships only as .7z and .msi, and System32's tar can't
# read the .7z (LZMA with BCJ2), but bsdtar can (ADR 0017), so neither Server Core nor a 7-Zip download is needed
# before the final stage. The stage's files are copied out, so its OS version doesn't matter, but it matches
# WINDOWS_VERSION so the host can run it with process isolation. The download goes to a file first; piping it into
# tar is forbidden (tests/test_no_tar_from_pipe.py).
# FAR_BUILD and FAR_DATE identify the stable build listed on https://www.farmanager.com/download.php, which publishes
# no checksums: FAR_SHA256 was computed from that download. Update all three together.
FROM zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}-pwsh AS fetch
SHELL ["pwsh", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
ENV FAR_BUILD=6699 \
    FAR_DATE=20260614 \
    FAR_SHA256=0030e9bf36afded1fd0647fb105446a93c49ce15db32d554fad62146c0665063
RUN curl.exe -fsSL -o C:\far.7z ('https://www.farmanager.com/files/Far30b' + ${env:FAR_BUILD} + '.x64.' + ${env:FAR_DATE} + '.7z'); \
    if ($LASTEXITCODE) { throw ('far.7z download failed: ' + $LASTEXITCODE) }; \
    if ((Get-FileHash C:\far.7z).Hash -ne ${env:FAR_SHA256}) { throw 'far.7z has the wrong SHA-256' }; \
    New-Item -ItemType Directory C:\far | Out-Null; \
    tar -xf C:\far.7z -C C:\far; \
    if ($LASTEXITCODE) { throw ('tar could not unpack far.7z: ' + $LASTEXITCODE) }

FROM ${BASE_IMAGE}
ENV FAR_VERSION=3.0.6699 \
    FAR_DIR="C:\\Program Files\\Far Manager"
SHELL ["cmd", "/S", "/C"]

# Far statically links the VC runtime (no vcruntime140.dll or msvcp140.dll imports), so no DLLs need staging.
COPY --from=fetch ["C:/far/", "C:/Program Files/Far Manager/"]

# servercore runs as ContainerAdministrator by default; nanoserver runs as ContainerUser.
# Switch so this image behaves like the nanoserver ones (non-admin user, PATH in that user's HKCU).
USER ContainerUser

# Put Far on ContainerUser's PATH, which is empty here, so nothing is appended. ltsc2019 has no HKCU\Environment key
# until it is created, so create it first if needed. One RUN, because each one starts a container.
RUN (reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH) && setx PATH "%FAR_DIR%"

# The container has two users, ContainerAdministrator and ContainerUser.
# They don't show up in the Net User command, but they have profile directories with registry hives.
WORKDIR C:/users/containeruser

# Set the entry point and default command
ENTRYPOINT ["cmd", "/S", "/C"]
