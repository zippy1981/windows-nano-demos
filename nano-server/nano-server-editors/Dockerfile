# windows-nano-editors: Console text editors on Nano Server: GNU nano and Helix, plus Microsoft Edit from the base image.
# Docker Hub categories: developer-tools
#
# The editors need a console: run the image with docker run -it. CI runs only their non-interactive checks.
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-editors):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-editors:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base for WINDOWS_VERSION, which has bsdtar, jq,
# Microsoft Edit and the Visual C++ runtime (ADR 0017). CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}

# Downloads are checked and unpacked in a throwaway Server Core stage, which has PowerShell. Helix needs
# vcruntime140.dll and vcruntime140_1.dll, which the base image ships in System32.
FROM mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION} AS fetch
SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
# Docker passes each RUN to powershell -Command, and Windows argument parsing strips double quotes, so strings with
# spaces use single quotes and + rather than "...".
# 7-Zip unpacks the downloads. The nano zip uses Deflate64, which Windows PowerShell's Expand-Archive can't decompress
# and tar.exe silently writes as zero bytes. 7zr.exe only reads .7z, so it unpacks the "extra" package that holds 7za.exe.
# The base's bsdtar can't read Deflate64 either. 7-Zip can go once a base with the fix is published:
# https://github.com/zippy1981/windows-nano-baseimages/issues/7
ENV SEVENZIP_VERSION=26.06 \
    SEVENZR_SHA256=E80DB2DAD715A6C5ADABE292D31ED54E11F4E9B99CA349827B50573B175891BC \
    SEVENZIP_EXTRA_SHA256=396C180F12D2247C24B0B1FCD482C6FC2A2700F61211FFEDE1061DD971F5E104
RUN $base = 'https://github.com/ip7z/7zip/releases/download/' + ${env:SEVENZIP_VERSION}; \
    $extra = '7z' + (${env:SEVENZIP_VERSION} -replace '[.]', '') + '-extra.7z'; \
    curl.exe -fsSLo C:\7zr.exe ($base + '/7zr.exe'); if ($LASTEXITCODE) { throw ('7zr.exe download failed: ' + $LASTEXITCODE) }; \
    curl.exe -fsSLo C:\7z-extra.7z ($base + '/' + $extra); if ($LASTEXITCODE) { throw ($extra + ' download failed: ' + $LASTEXITCODE) }; \
    if ((Get-FileHash C:\7zr.exe).Hash -ne ${env:SEVENZR_SHA256}) { throw '7zr.exe has the wrong SHA-256' }; \
    if ((Get-FileHash C:\7z-extra.7z).Hash -ne ${env:SEVENZIP_EXTRA_SHA256}) { throw ($extra + ' has the wrong SHA-256') }; \
    C:\7zr.exe x C:\7z-extra.7z -oC:\7z -y | Out-Null; if ($LASTEXITCODE) { throw ('7zr exited with ' + $LASTEXITCODE) }; \
    Remove-Item C:\7zr.exe, C:\7z-extra.7z
COPY Get-VerifiedZip.ps1 C:/build/Get-VerifiedZip.ps1

# One RUN per editor, so a broken one is easy to drop. Each download is pinned by version and SHA-256. Microsoft Edit
# isn't downloaded: the base image has it on PATH (ADR 0017).

# GNU nano 7.2 for Windows (okibcn), built with MinGW against the UCRT. The port's last release is from 2023.
ENV NANO_VERSION=7.2-22.1 \
    NANO_SHA256=CE50A799A5FAE37AC36FF2D7F3680968CA4AF11A808EDAD96BCCE746C13CCD20
RUN C:\build\Get-VerifiedZip.ps1 -Destination C:\x\nano -Executable nano.exe \
      -Url "https://github.com/okibcn/nano-for-windows/releases/download/v${env:NANO_VERSION}/nano-for-windows_win64_v${env:NANO_VERSION}.zip" \
      -Sha256 ${env:NANO_SHA256}; \
    New-Item -ItemType Directory C:\editors\nano | Out-Null; \
    Move-Item C:\x\nano\nano.exe, C:\x\nano\.nanorc, C:\x\nano\LICENSE C:\editors\nano

ENV HELIX_VERSION=25.07.1 \
    HELIX_SHA256=5C8325CED8BACD8418D62706F669E96D9C3578A9237526E34D546900CBC049B6
RUN C:\build\Get-VerifiedZip.ps1 -Destination C:\x\helix -Executable "helix-${env:HELIX_VERSION}-x86_64-windows\hx.exe" \
      -Url "https://github.com/helix-editor/helix/releases/download/${env:HELIX_VERSION}/helix-${env:HELIX_VERSION}-x86_64-windows.zip" \
      -Sha256 ${env:HELIX_SHA256}; \
    Move-Item "C:\x\helix\helix-${env:HELIX_VERSION}-x86_64-windows" C:\editors\helix; \
    Remove-Item -Recurse C:\editors\helix\contrib

FROM ${BASE_IMAGE}

COPY --from=fetch ["C:/editors/nano", "C:/Program Files/nano"]
COPY --from=fetch ["C:/editors/helix", "C:/Program Files/helix"]

# The nano port can't start on ltsc2019: it exits with 0xC0000139 (STATUS_ENTRYPOINT_NOT_FOUND), because it imports
# a function ltsc2019's DLLs don't have. Leave it out there rather than ship a program that can't run.
ARG WINDOWS_VERSION
USER ContainerAdministrator
RUN if "%WINDOWS_VERSION%"=="2019" rmdir /s /q "C:\Program Files\nano"
USER ContainerUser

# Helix finds its themes and tree-sitter grammars through HELIX_RUNTIME
ENV HELIX_RUNTIME="C:\\Program Files\\helix\\runtime"
ENV PATH="C:\\Program Files\\nano;C:\\Program Files\\helix;${PATH}"
