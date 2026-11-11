# windows-nano-mysql: MySQL 8.4 LTS server and client tools on Nano Server, configured with MYSQL_* variables.
# Docker Hub categories: databases-and-storage
#
# Build from this folder (build.cmd does the same, and also tags zippy1981/windows-nano-mysql):
#   docker build --memory 4g --build-arg WINDOWS_VERSION=2022 -t windows-nano-mysql:2022 .
# Each build argument is described where it is declared below.

# Windows Server LTSC version to build for: 2019, 2022 or 2025 (the default). Set with --build-arg WINDOWS_VERSION=2022.
ARG WINDOWS_VERSION=2025
# The image the final stage is built on. Defaults to nanoserver-base for WINDOWS_VERSION, which has bsdtar, jq,
# Microsoft Edit and the Visual C++ runtime (ADR 0017). CI pins it to a digest.
# Set with --build-arg BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022.
ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}

# mysqld.exe and the client tools need the Visual C++ runtime (vcruntime140.dll and vcruntime140_1.dll, and
# msvcp140.dll for mysqld). The base image ships all three in System32.
FROM ${BASE_IMAGE}

# Pinned version (8.4 is the current LTS series)
ENV MYSQL_VERSION=8.4.13

# Install location. This has to be a separate ENV instruction: ENV can't reference variables set in the same instruction.
ENV MYSQL_DIR="C:\\mysql"

USER ContainerAdministrator

# Download to a file first, then extract to C:\ (the zip holds one mysql-<version>-winx64 folder). A zip piped
# into tar loses its first ~64 KB on Windows, and tests/test_no_tar_from_pipe.py forbids piping here for good,
# whatever the upstream fix does (https://github.com/zippy1981/windows-nano-baseimages/issues/8).
# Unpacked it is ~1.7 GB, mostly things a server image doesn't need, so strip them in the same layer:
#  - *.pdb debug symbols (mysqld.pdb alone is 600 MB) and *.lib import libraries
#  - the debug builds of the DLLs and plugins (bin\*-debug.dll, lib\plugin\debug)
#  - the MeCab full-text parser dictionaries (lib\mecab, only used by the optional mecab plugin)
#  - C headers and docs
RUN mkdir C:\dl && \
    curl -fsSLo C:\dl\mysql.zip https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-%MYSQL_VERSION%-winx64.zip && \
    tar -xf C:\dl\mysql.zip -C C:\ && \
    move C:\mysql-%MYSQL_VERSION%-winx64 %MYSQL_DIR% && \
    rmdir /s /q C:\dl && \
    del /q %MYSQL_DIR%\bin\*.pdb %MYSQL_DIR%\bin\*.lib %MYSQL_DIR%\bin\*-debug.dll && \
    rmdir /s /q %MYSQL_DIR%\lib\plugin\debug %MYSQL_DIR%\lib\mecab %MYSQL_DIR%\include %MYSQL_DIR%\docs && \
    del /q %MYSQL_DIR%\lib\*.lib

# mysqld and the client tools on the path
ENV PATH="C:\\mysql\\bin;${PATH}"

# The data directory is a volume. Folders created under C:\ inherit Modify for Authenticated Users
# (nanoserver has no icacls), so ContainerUser can write to it once it exists in the image.
RUN mkdir C:\mysql\data

COPY docker-entrypoint.cmd C:/docker-entrypoint.cmd

# mysqld runs fine as ContainerUser, so the server isn't run as an administrator
USER ContainerUser
VOLUME ["C:/mysql/data"]
EXPOSE 3306 33060

# First start initializes the data directory and sets the root password from MYSQL_ROOT_PASSWORD.
# Anything other than the default command (mysql, mysqldump, cmd, ...) is run as given.
ENTRYPOINT ["C:\\docker-entrypoint.cmd"]
CMD ["mysqld"]
