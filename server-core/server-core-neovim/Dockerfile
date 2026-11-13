# windows-servercore-neovim: Neovim and MinGit on Server Core. Run it with docker run -it.
# Docker Hub categories: developer-tools
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-servercore-neovim):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-servercore-neovim:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# Neovim can NOT run on nanoserver, so this image is based on servercore.
# nvim.exe imports kernel32!DebugBreakProcess, which the nanoserver ltsc2019, ltsc2022 and ltsc2025 kernel32 forwarder
# doesn't export, so it exits with 0xC0000139 (STATUS_ENTRYPOINT_NOT_FOUND). Nanoserver also lacks netapi32.dll,
# which nvim.exe imports as well.
# Set with --build-arg BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2022-amd64.
ARG BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64

# nvim.exe needs the Visual C++ runtime (vcruntime140.dll). Server Core doesn't ship it. nanoserver-base does
# (ADR 0017), so it is copied from there.
FROM zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION} AS vcrt

FROM ${BASE_IMAGE}

# Pinned versions.
# MinGit goes in "MinGit", not "Git": its etc\gitconfig includes "C:/Program Files/Git/etc/gitconfig", so installed
# there git includes itself until it fails with "exceeded maximum include depth".
ENV \
    NEOVIM_VERSION=0.12.6 \
    NEOVIM_DIR="C:\\Program Files\\nvim-win64" \
    MINGIT_TAG=v2.56.0.windows.4 \
    MINGIT_VERSION=2.56.0.4 \
    MINGIT_DIR="C:\\Program Files\\MinGit"

SHELL ["cmd", "/S", "/C"]

COPY --from=vcrt ["C:/Windows/System32/vcruntime140.dll", "C:/Windows/System32/vcruntime140_1.dll", "C:/Windows/System32/msvcp140.dll", "C:/Windows/System32/"]

# The zip unpacks to nvim-win64\, which is NEOVIM_DIR.
# Download to a file, then extract: piping curl into tar can silently skip entries.
# The zip's own DbgHelp.dll is deleted. With it in the image layer, nvim.exe exits with 255 and no output on ltsc2022
# under Hyper-V isolation (0xC0000142 as ContainerUser), although the same files run when they are copied into a
# running container. Without it nvim loads the dbghelp.dll of Windows, which it only uses for crash reports.
RUN curl -fL -o C:\nvim.zip https://github.com/neovim/neovim/releases/download/v%NEOVIM_VERSION%/nvim-win64.zip && \
    tar -xf C:\nvim.zip -C "%ProgramFiles%" && \
    del C:\nvim.zip "%NEOVIM_DIR%\bin\DbgHelp.dll"

# MinGit, the non-busybox flavour, so plugin managers such as lazy.nvim can clone plugins.
RUN mkdir "%MINGIT_DIR%" && \
    curl -fL -o C:\mingit.zip https://github.com/git-for-windows/git/releases/download/%MINGIT_TAG%/MinGit-%MINGIT_VERSION%-64-bit.zip && \
    tar -xf C:\mingit.zip -C "%MINGIT_DIR%" && \
    del C:\mingit.zip

# servercore runs as ContainerAdministrator by default; nanoserver runs as ContainerUser.
# Switch so this image behaves like the nanoserver ones (non-admin user, PATH in that user's HKCU).
USER ContainerUser

# Add what we installed to the user PATH. On 2019 the HKCU\Environment key must exist before setx can write to it.
RUN reg query HKCU\Environment 2> NUL || reg add HKCU\Environment /v PATH
RUN setx PATH "%NEOVIM_DIR%\bin;%MINGIT_DIR%\cmd"

# The container has two users, ContainerAdministrator and ContainerUser.
# They don't show up in the Net User command, but they have profile directories with registry hives.
WORKDIR C:/users/containeruser

# Set the entry point and default command
ENTRYPOINT ["cmd", "/S", "/C"]
