# windows-nano-reactos-tools: Command-line tools Nano Server lacks (more, tree and more), from ReactOS on Nano Server.
# Docker Hub categories: developer-tools, operating-systems
#
# Licensing: the ReactOS programs are GPL-2.0-or-later (some LGPL-2.1 files from Wine). The image carries
# COPYING, COPYING.LIB and SOURCE.md next to the tools. The pinned source archive must be mirrored as a
# release asset before this image is published; see SOURCE.md. This is an engineering reading, not legal advice.
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-reactos-tools):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-reactos-tools:2022 .
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

# ---------- fetch: ReactOS tools, the __chkstk shim, and the import patch ----------
FROM ${FETCH_IMAGE} AS fetch
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY tools.txt C:/fetch/
COPY scripts/ C:/fetch/scripts/
COPY shim/ C:/fetch/shim/
RUN C:\fetch\scripts\Fetch-Reactos.ps1 -ToolsFile C:\fetch\tools.txt -OutDir C:\ros-out -ContextDir C:\fetch

# ---------- check: every import of every patched tool must resolve against this exact base ----------
FROM ${BASE_IMAGE} AS check
ENV POWERSHELL_VERSION=7.6.9
RUN mkdir C:\Users\ContainerUser\pwsh && \
    curl -fsSL --retry 5 --retry-delay 5 -o C:\Users\ContainerUser\pwsh.zip https://github.com/PowerShell/PowerShell/releases/download/v%POWERSHELL_VERSION%/PowerShell-%POWERSHELL_VERSION%-win-x64.zip && \
    tar -xf C:\Users\ContainerUser\pwsh.zip -C C:\Users\ContainerUser\pwsh && \
    del C:\Users\ContainerUser\pwsh.zip
COPY --from=fetch ["C:/ros-out/", "C:/ros-out/"]
COPY scripts/ C:/scripts/
RUN C:\Users\ContainerUser\pwsh\pwsh.exe -NoLogo -NoProfile -File C:\scripts\Test-PeImports.ps1 -Path C:\ros-out -System32 C:\Windows\System32

# ---------- final ----------
FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later AND LGPL-2.1-or-later" \
      org.reactos.commit="e25c37366b65d94985522a931f76351d6b244234"

COPY --from=check ["C:/ros-out/", "C:/Program Files/reactos-tools/"]
COPY ["licenses/", "C:/Program Files/reactos-tools/"]
COPY ["SOURCE.md", "C:/Program Files/reactos-tools/"]
COPY tests/ C:/tests/
COPY tools.txt C:/tests/tools.txt

USER ContainerAdministrator
RUN mkdir C:\work && icacls C:\work /grant "User Manager\ContainerUser:(OI)(CI)M" && \
    icacls C:\tests /grant "User Manager\ContainerUser:(OI)(CI)M"
USER ContainerUser

# The ReactOS tools go after the system PATH (the user PATH is appended to it), so nothing nanoserver
# ships is shadowed. On ltsc2019 the user's Environment key has to exist before setx can add to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "C:\Program Files\reactos-tools"

WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["cmd"]
