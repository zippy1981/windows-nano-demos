# windows-nano-powershell-sqlite-odbc: PowerShell 7 with the Stackable SQLite ODBC driver, system-wide.
# Docker Hub categories: languages-and-frameworks, developer-tools, databases-and-storage
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-powershell-sqlite-odbc):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-powershell-sqlite-odbc:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base's -pwsh tag for WINDOWS_VERSION: PowerShell 7,
# bsdtar, jq, Microsoft Edit and the Visual C++ runtime. CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022-pwsh.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}-pwsh

# Downloads are checked in a throwaway Server Core stage, which has Windows PowerShell. It also stages the
# Windows ODBC Driver Manager files that Nano Server does not ship: DEVELOPER.md's API probe lists odbc32 as
# missing on Nano Server, and the driver itself imports odbccp32.dll, so without these copies every ODBC
# call (and loading the driver at all) fails with 0xC0000135 (STATUS_DLL_NOT_FOUND). The files come from the
# Server Core image of the same Windows version, so their versions match the final image.
FROM mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64 AS fetch
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Stackable ODBC driver for SQLite: https://github.com/stackabletech/stackable-odbc-sqlite/releases.
# SQLite is compiled into the driver, so there is no separate SQLite to install.
ENV STACKABLE_ODBC_VERSION=0.1.0 \
    STACKABLE_ODBC_SHA256=4AD157368415E809F817E3087DB9F6DE36634F1C437B5689106005FBB56C45F3

# Download the release zip to a file, check its SHA-256, then unpack it. Never pipe a download into an
# extractor: the pipe form silently drops entries on Windows.
RUN $zip = 'C:\stackable-odbc-sqlite.zip'; \
    curl.exe -fsSLo $zip ('https://github.com/stackabletech/stackable-odbc-sqlite/releases/download/v' + $env:STACKABLE_ODBC_VERSION + '/stackable-odbc-sqlite-' + $env:STACKABLE_ODBC_VERSION + '-windows-x64.zip'); \
    if ($LASTEXITCODE) { throw ('driver download failed: ' + $LASTEXITCODE) }; \
    if ((Get-FileHash $zip).Hash -ne $env:STACKABLE_ODBC_SHA256) { throw 'driver zip has the wrong SHA-256' }; \
    Expand-Archive -Path $zip -DestinationPath C:\driver; \
    Remove-Item $zip; \
    $dll = 'C:\driver\stackable_odbc_sqlite.dll'; \
    $stream = [IO.File]::OpenRead($dll); $mz = $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A; $stream.Dispose(); \
    if (-not $mz) { throw 'stackable_odbc_sqlite.dll is not a Windows executable after extraction' }; \
    New-Item -ItemType Directory -Path C:\package | Out-Null; \
    Copy-Item $dll, 'C:\driver\configure-dsn.ps1', 'C:\driver\LICENSE' -Destination C:\package; \
    New-Item -ItemType Directory -Path C:\odbc | Out-Null; \
    foreach ($name in 'odbc32.dll', 'odbccp32.dll', 'odbcint.dll', 'odbcad32.exe', 'odbcconf.exe') { \
        $source = Join-Path $env:SystemRoot ('System32\' + $name); \
        if (-not (Test-Path $source)) { throw ($name + ' is missing from the Server Core stage') }; \
        Copy-Item $source -Destination C:\odbc \
    }; \
    Get-ChildItem -Recurse -File C:\package, C:\odbc | Format-Table -AutoSize Length, FullName

FROM ${BASE_IMAGE}

# The ODBC Driver Manager (odbc32.dll, odbccp32.dll and friends) from the Server Core stage above.
COPY --from=fetch C:/odbc/ C:/Windows/System32/
COPY --from=fetch ["C:/package", "C:/Program Files/Stackable/ODBC"]

# Register the driver system-wide (HKLM), with the same entries the release's install.bat writes through
# odbcconf's INSTALLDRIVER. Registering needs an administrator; the smoke test checks the HKLM entry and
# connects as ContainerUser, so a per-user registration would fail it. The entries are written with
# reg.exe directly: odbcconf.exe (copied in above, and kept in the image for DSN work) exits with -10 in
# this stage on every Windows version in CI, before printing anything.
USER ContainerAdministrator
RUN reg add "HKLM\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite" /v Driver /t REG_SZ /d "C:\Program Files\Stackable\ODBC\stackable_odbc_sqlite.dll" /f && \
    reg add "HKLM\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite" /v Setup /t REG_SZ /d "C:\Program Files\Stackable\ODBC\stackable_odbc_sqlite.dll" /f && \
    reg add "HKLM\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite" /v UsageCount /t REG_DWORD /d 1 /f && \
    reg add "HKLM\SOFTWARE\ODBC\ODBCINST.INI\ODBC Drivers" /v stackable_odbc_sqlite /t REG_SZ /d Installed /f && \
    reg query "HKLM\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite" /v Driver
USER ContainerUser

# Where the driver is installed, for scripts that want the path without hard-coding it.
ENV STACKABLE_ODBC_DIR="C:\\Program Files\\Stackable\\ODBC"

WORKDIR C:/users/containeruser

ENTRYPOINT ["cmd", "/S", "/C"]
CMD ["pwsh"]
