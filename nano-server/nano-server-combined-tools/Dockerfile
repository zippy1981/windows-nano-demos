# windows-nano-combined-tools: Command-line tools Nano Server lacks, best implementation per tool, on Nano Server.
# Docker Hub categories: developer-tools, operating-systems
#
# Licensing: Wine programs are LGPL-2.1-or-later, ReactOS programs GPL-2.0-or-later (some LGPL-2.1 files).
# The image carries the licence texts and SOURCE.md in C:\tools\combined, next to the tools. The ReactOS source for
# the release is published as a release asset of this repository; SOURCE.md gives the link and its SHA-256. Not legal advice.
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-combined-tools). The build
# context is nano-server\, because the fetch and check stages share scripts and shim with the other tool images:
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -f Dockerfile -t windows-nano-combined-tools:2022 ..
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the check and final stages are built on. Defaults to nanoserver-base for WINDOWS_VERSION: bsdtar, jq,
# Microsoft Edit and the Visual C++ runtime (ADR 0017). CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}
# The image that downloads Wine and ReactOS, for every WINDOWS_VERSION. Server Core has Windows PowerShell
# and a tar that reads the zstd data in WineHQ's .deb; the extracted PE files are the same for every version.
# Set with --build-arg FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64.
ARG FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64
# The ReactOS release the tools come from. 4.17 is pinned in shared-tools/scripts/Fetch-Reactos.ps1; a version without
# a pin there fails the build. Set with --build-arg REACTOS_VERSION=4.17. It is also the org.reactos.version label.
ARG REACTOS_VERSION=4.17

# ---------- fetch Wine: the unmodified Wine PE programs ----------
FROM ${FETCH_IMAGE} AS fetch-wine
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY shared-tools/scripts/fetch-wine.ps1 C:/fetch/
COPY nano-server-combined-tools/wine-tools.txt C:/fetch/
RUN C:\fetch\fetch-wine.ps1 -ToolsFile C:\fetch\wine-tools.txt -OutDir C:\wine-out

# ---------- fetch ReactOS: the ReactOS tools, the __chkstk shim, and the import patch ----------
FROM ${FETCH_IMAGE} AS fetch-reactos
ARG REACTOS_VERSION
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY nano-server-combined-tools/reactos-tools.txt C:/fetch/
COPY shared-tools/scripts/ C:/fetch/scripts/
COPY shared-tools/shim/ C:/fetch/shim/
RUN C:\fetch\scripts\Fetch-Reactos.ps1 -ReactosVersion $env:REACTOS_VERSION -ToolsFile C:\fetch\reactos-tools.txt -OutDir C:\ros-out -ContextDir C:\fetch

# ---------- Server Core of the same version: certoc.exe, the third source ----------
FROM mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64 AS servercore

# ---------- select and check: pick one implementation per tool, then verify every import ----------
FROM ${BASE_IMAGE} AS check
ENV POWERSHELL_VERSION=7.6.9
RUN mkdir C:\Users\ContainerUser\pwsh && \
    curl -fsSL --retry 5 --retry-delay 5 -o C:\Users\ContainerUser\pwsh.zip https://github.com/PowerShell/PowerShell/releases/download/v%POWERSHELL_VERSION%/PowerShell-%POWERSHELL_VERSION%-win-x64.zip && \
    tar -xf C:\Users\ContainerUser\pwsh.zip -C C:\Users\ContainerUser\pwsh && \
    del C:\Users\ContainerUser\pwsh.zip
COPY --from=fetch-wine ["C:/wine-out/", "C:/wine-out/"]
COPY --from=fetch-reactos ["C:/ros-out/", "C:/ros-out/"]
COPY --from=servercore ["C:/Windows/System32/certoc.exe", "C:/sc-out/"]
COPY nano-server-combined-tools/tool-sources.txt C:/tool-sources.txt
COPY shared-tools/scripts/ C:/scripts/
COPY nano-server-combined-tools/scripts/Select-Tools.ps1 C:/scripts/
RUN C:\Users\ContainerUser\pwsh\pwsh.exe -NoLogo -NoProfile -File C:\scripts\Select-Tools.ps1 -Manifest C:\tool-sources.txt -WineDir C:\wine-out -ReactosDir C:\ros-out -ServercoreDir C:\sc-out -OutDir C:\out
RUN C:\Users\ContainerUser\pwsh\pwsh.exe -NoLogo -NoProfile -File C:\scripts\Test-PeImports.ps1 -Path C:\out -System32 C:\Windows\System32

# ---------- final ----------
FROM ${BASE_IMAGE}
ARG REACTOS_VERSION
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later AND LGPL-2.1-or-later" \
      org.reactos.version="${REACTOS_VERSION}" \
      org.winehq.version="11.0"

# Without this, Wine's stub code paths print fixme: lines to stderr. winecrt0's fallback honours it on Windows.
ENV WINEDEBUG=-all

COPY --from=check ["C:/out/", "C:/tools/combined/"]
COPY ["nano-server-combined-tools/licenses/", "C:/tools/combined/"]
COPY ["nano-server-combined-tools/SOURCE.md", "C:/tools/combined/"]
COPY nano-server-combined-tools/tests/ C:/tests/
COPY nano-server-combined-tools/tool-sources.txt nano-server-combined-tools/wine-tools.txt nano-server-combined-tools/reactos-tools.txt C:/tests/

USER ContainerAdministrator
RUN mkdir C:\work && icacls C:\work /grant "User Manager\ContainerUser:(OI)(CI)M" && \
    icacls C:\tests /grant "User Manager\ContainerUser:(OI)(CI)M"
USER ContainerUser

# The tools go after the system PATH (the user PATH is appended to it), so nothing nanoserver
# ships is shadowed. On ltsc2019 the user's Environment key has to exist before setx can add to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "C:\tools\combined"

WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["cmd"]
