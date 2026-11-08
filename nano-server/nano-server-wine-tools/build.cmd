@echo off
setlocal
rem WINDOWS_VERSION picks the LTSC base: 2019, 2022 or 2025 (default).
rem BASE_IMAGE optionally overrides the nanoserver base image entirely.
rem The Dockerfile downloads the Wine programs and their source tarball itself, in a Server Core ltsc2025 stage.
if not defined WINDOWS_VERSION set "WINDOWS_VERSION=2025"
set "BUILD_ARGS=--build-arg WINDOWS_VERSION=%WINDOWS_VERSION%"
if defined BASE_IMAGE set "BUILD_ARGS=%BUILD_ARGS% --build-arg BASE_IMAGE=%BASE_IMAGE%"
rem --memory 4g: the Hyper-V default of 1 GB hangs builds
docker build --memory 4g %BUILD_ARGS% -t windows-nano-wine-tools:%WINDOWS_VERSION% -t zippy1981/windows-nano-wine-tools:%WINDOWS_VERSION% -f "%~dp0Dockerfile" "%~dp0.."
