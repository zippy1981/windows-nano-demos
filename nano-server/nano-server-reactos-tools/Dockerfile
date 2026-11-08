# windows-nano-reactos-tools: Command-line tools Nano Server lacks (more, tree and more), from ReactOS on Nano Server.
# Docker Hub categories: developer-tools, operating-systems
#
# Licensing: the ReactOS programs are GPL-2.0-or-later (some LGPL-2.1 files from Wine). The image carries
# COPYING, COPYING.LIB and SOURCE.md in C:\tools\reactos, next to the tools. The ReactOS source for the release is
# published as a release asset of this repository; SOURCE.md gives the link and its SHA-256. This is an engineering
# reading, not legal advice.
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-reactos-tools). The build
# context is nano-server\, because the fetch and check stages share scripts and shim with the other tool images:
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -f Dockerfile -t windows-nano-reactos-tools:2022 ..
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to Nano Server for WINDOWS_VERSION; CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64
# The image that downloads ReactOS and builds the shim, for every WINDOWS_VERSION. Server Core has Windows
# PowerShell and a tar that handles the downloads; the extracted PE files are the same for every version.
# Set with --build-arg FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64.
ARG FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64
# The ReactOS release the tools come from. 4.17 is pinned in shared-tools/scripts/Fetch-Reactos.ps1; a version without
# a pin there fails the build. Set with --build-arg REACTOS_VERSION=4.17. It is also the org.reactos.version label.
ARG REACTOS_VERSION=4.17

# ---------- fetch: ReactOS tools, the __chkstk shim, and the import patch ----------
FROM ${FETCH_IMAGE} AS fetch
ARG REACTOS_VERSION
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY shared-tools/scripts/ C:/fetch/scripts/
COPY shared-tools/shim/ C:/fetch/shim/
COPY nano-server-reactos-tools/tools.txt C:/fetch/
RUN C:\fetch\scripts\Fetch-Reactos.ps1 -ReactosVersion $env:REACTOS_VERSION -ToolsFile C:\fetch\tools.txt -OutDir C:\ros-out -ContextDir C:\fetch

# ---------- check: every import of every patched tool must resolve against this exact base ----------
FROM ${BASE_IMAGE} AS check
ENV POWERSHELL_VERSION=7.6.9
RUN mkdir C:\Users\ContainerUser\pwsh && \
    curl -fsSL --retry 5 --retry-delay 5 -o C:\Users\ContainerUser\pwsh.zip https://github.com/PowerShell/PowerShell/releases/download/v%POWERSHELL_VERSION%/PowerShell-%POWERSHELL_VERSION%-win-x64.zip && \
    tar -xf C:\Users\ContainerUser\pwsh.zip -C C:\Users\ContainerUser\pwsh && \
    del C:\Users\ContainerUser\pwsh.zip
COPY --from=fetch ["C:/ros-out/", "C:/ros-out/"]
COPY shared-tools/scripts/Test-PeImports.ps1 C:/scripts/
RUN C:\Users\ContainerUser\pwsh\pwsh.exe -NoLogo -NoProfile -File C:\scripts\Test-PeImports.ps1 -Path C:\ros-out -System32 C:\Windows\System32

# ---------- final ----------
FROM ${BASE_IMAGE}
ARG REACTOS_VERSION
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later AND LGPL-2.1-or-later" \
      org.reactos.version="${REACTOS_VERSION}"

COPY --from=check ["C:/ros-out/", "C:/tools/reactos/"]
COPY ["nano-server-reactos-tools/licenses/", "C:/tools/reactos/"]
COPY ["nano-server-reactos-tools/SOURCE.md", "C:/tools/reactos/"]
COPY nano-server-reactos-tools/tests/ C:/tests/
COPY nano-server-reactos-tools/tools.txt C:/tests/tools.txt

USER ContainerAdministrator
RUN mkdir C:\work && icacls C:\work /grant "User Manager\ContainerUser:(OI)(CI)M" && \
    icacls C:\tests /grant "User Manager\ContainerUser:(OI)(CI)M"
USER ContainerUser

# The ReactOS tools go after the system PATH (the user PATH is appended to it), so nothing nanoserver
# ships is shadowed. On ltsc2019 the user's Environment key has to exist before setx can add to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "C:\tools\reactos"

WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["cmd"]
