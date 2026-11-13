@echo off
setlocal
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2025
rem The Visual C++ runtime comes from a build stage in the Dockerfile, so there are no host DLLs to stage.
set BASE_IMAGE_ARG=
if not "%BASE_IMAGE%"=="" set BASE_IMAGE_ARG=--build-arg "BASE_IMAGE=%BASE_IMAGE%"
rem Hyper-V isolated builds default to a 1 GB memory limit and can hang, so give them 4 GB.
docker build --memory 4g --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% %BASE_IMAGE_ARG% -t windows-servercore-neovim:%WINDOWS_VERSION% -t zippy1981/windows-servercore-neovim:%WINDOWS_VERSION% "%~dp0."
