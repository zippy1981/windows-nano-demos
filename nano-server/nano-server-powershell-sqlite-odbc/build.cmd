@echo off
setlocal
rem WINDOWS_VERSION picks the LTSC base: 2019, 2022 or 2025 (default).
rem BASE_IMAGE optionally overrides the nanoserver -pwsh base image entirely.
if not defined WINDOWS_VERSION set "WINDOWS_VERSION=2025"
set "BUILD_ARGS=--build-arg WINDOWS_VERSION=%WINDOWS_VERSION%"
if defined BASE_IMAGE set "BUILD_ARGS=%BUILD_ARGS% --build-arg BASE_IMAGE=%BASE_IMAGE%"
rem --memory 4g: the Hyper-V default of 1 GB hangs builds
docker build --memory 4g %BUILD_ARGS% -t windows-nano-powershell-sqlite-odbc:%WINDOWS_VERSION% -t zippy1981/windows-nano-powershell-sqlite-odbc:%WINDOWS_VERSION% "%~dp0."
