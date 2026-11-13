@echo off
setlocal
rem Scaffolded by scripts/New-NanoServerImage.ps1. Adjust the build steps to match the artifact.
rem Copy any host DLLs the image needs into .\system32 here.
if not defined WINDOWS_VERSION set "WINDOWS_VERSION=2025"
set "BUILD_ARGS=--build-arg WINDOWS_VERSION=%WINDOWS_VERSION%"
if defined BASE_IMAGE set "BUILD_ARGS=%BUILD_ARGS% --build-arg BASE_IMAGE=%BASE_IMAGE%"
rem FREEPASCAL_VERSION is optional. Unset builds the Dockerfile's default.
if not defined FREEPASCAL_VERSION set "FREEPASCAL_VERSION=3.2.2"
set "BUILD_ARGS=%BUILD_ARGS% --build-arg FREEPASCAL_VERSION=%FREEPASCAL_VERSION%"
set "TAGS=-t windows-nano-freepascal:%WINDOWS_VERSION% -t zippy1981/windows-nano-freepascal:%WINDOWS_VERSION% -t windows-nano-freepascal:%FREEPASCAL_VERSION%-%WINDOWS_VERSION% -t zippy1981/windows-nano-freepascal:%FREEPASCAL_VERSION%-%WINDOWS_VERSION%"
docker build --memory 4g %BUILD_ARGS% %TAGS% "%~dp0."
