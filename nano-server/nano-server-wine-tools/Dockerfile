# windows-nano-wine-tools: Command-line tools Nano Server lacks (find, fc and more), from Wine 11.0 on Nano Server.
#
# Licensing: the Wine programs are LGPL-2.1-or-later. The image carries their complete corresponding source, the
# unmodified wine-11.0.tar.xz release tarball from WineHQ (pinned by SHA-256, with WineHQ's signature next to it), in
# C:\Program Files\wine-tools\source, next to COPYING.LIB, LICENSE, AUTHORS and SOURCE.md. See SOURCE.md.
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-wine-tools):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-wine-tools:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to Nano Server for WINDOWS_VERSION; CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64
# The image that downloads and unpacks Wine, for every WINDOWS_VERSION. It must be ltsc2025 or newer: WineHQ's .deb
# holds a zstd-compressed tar, and only ltsc2025's tar.exe reads zstd. The PE files it extracts are the same for every
# Windows version. Set with --build-arg FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64.
ARG FETCH_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2025-amd64

# ---------- fetch: the Wine programs from WineHQ's .deb, and the matching source tarball ----------
FROM ${FETCH_IMAGE} AS fetch
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
COPY fetch-wine.ps1 tools.txt C:/fetch/
# The unmodified x86_64 PE programs listed in tools.txt, from the pinned wine-stable .deb (SHA-256 checked)
RUN C:\fetch\fetch-wine.ps1 -OutDir C:\wine-pe
# The corresponding source for those programs: WineHQ's release tarball and its detached signature.
# Docker passes RUN to powershell -Command with double quotes stripped, so strings use single quotes.
ENV WINE_SOURCE_SHA256=C07A6857933C1FC60DFF5448D79F39C92481C1E9DB5AA628DB9D0358446E0701
RUN $url = 'https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz'; \
    New-Item -ItemType Directory C:\wine-source | Out-Null; \
    curl.exe -fsSL --retry 5 --retry-delay 5 -o C:\wine-source\wine-11.0.tar.xz $url; \
    if ($LASTEXITCODE) { throw ('source tarball download failed: ' + $LASTEXITCODE) }; \
    curl.exe -fsSL --retry 5 --retry-delay 5 -o C:\wine-source\wine-11.0.tar.xz.sign ($url + '.sign'); \
    if ($LASTEXITCODE) { throw ('signature download failed: ' + $LASTEXITCODE) }; \
    $hash = (Get-FileHash C:\wine-source\wine-11.0.tar.xz).Hash; \
    if ($hash -ne ${env:WINE_SOURCE_SHA256}) { throw ('wine-11.0.tar.xz has SHA-256 ' + $hash) }

# ---------- check: every import of every Wine tool must resolve against this exact base ----------
FROM ${BASE_IMAGE} AS check
ENV POWERSHELL_VERSION=7.6.9
RUN mkdir C:\Users\ContainerUser\pwsh && \
    curl -fsSL --retry 5 --retry-delay 5 -o C:\Users\ContainerUser\pwsh.zip https://github.com/PowerShell/PowerShell/releases/download/v%POWERSHELL_VERSION%/PowerShell-%POWERSHELL_VERSION%-win-x64.zip && \
    tar -xf C:\Users\ContainerUser\pwsh.zip -C C:\Users\ContainerUser\pwsh && \
    del C:\Users\ContainerUser\pwsh.zip
COPY --from=fetch ["C:/wine-pe/", "C:/wine-pe/"]
COPY scripts/ C:/scripts/
RUN C:\Users\ContainerUser\pwsh\pwsh.exe -NoLogo -NoProfile -File C:\scripts\Test-PeImports.ps1 -Path C:\wine-pe -System32 C:\Windows\System32

# ---------- final ----------
FROM ${BASE_IMAGE}
# The Wine release the programs and the source tarball come from, recorded in a label. Changing it also needs new
# pins in fetch-wine.ps1 and above. Set with --build-arg WINE_VERSION=11.0.
ARG WINE_VERSION=11.0
LABEL org.opencontainers.image.licenses="LGPL-2.1-or-later" \
      org.winehq.version="${WINE_VERSION}"

# Without this, Wine's stub code paths print fixme: lines to stderr. winecrt0's fallback honours it on Windows.
ENV WINEDEBUG=-all

# Copying from the check stage makes the final stage depend on it, so the import check always runs.
COPY --from=check ["C:/wine-pe/", "C:/Program Files/wine-tools/"]
COPY ["licenses/", "C:/Program Files/wine-tools/"]
COPY ["SOURCE.md", "C:/Program Files/wine-tools/"]
COPY --from=fetch ["C:/wine-source/", "C:/Program Files/wine-tools/source/"]
COPY tests/ C:/tests/
COPY tools.txt C:/tests/tools.txt

# C:\work is scratch space for the tests (cabinets, hard links), writable by the default user.
USER ContainerAdministrator
RUN mkdir C:\work && icacls C:\work /grant "User Manager\ContainerUser:(OI)(CI)M" && \
    icacls C:\tests /grant "User Manager\ContainerUser:(OI)(CI)M"
USER ContainerUser

# The Wine tools go after the system PATH (the user PATH is appended to it), so nothing nanoserver
# ships is shadowed. On ltsc2019 the user's Environment key has to exist before setx can add to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "C:\Program Files\wine-tools"

# The container has two users, ContainerAdministrator and ContainerUser.
# They don't show up in the Net User command, but they have profile directories with registry hives.
WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["cmd"]
