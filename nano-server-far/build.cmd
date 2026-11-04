@echo off
setlocal
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2022
rem Far Manager statically links the VC runtime, so unlike nano-server-php there are no host DLLs to stage into system32.
rem The .7z is extracted in a servercore build stage instead of with a host copy of 7z.exe.
set BASE_IMAGE_ARG=
if not "%BASE_IMAGE%"=="" set BASE_IMAGE_ARG=--build-arg "BASE_IMAGE=%BASE_IMAGE%"
docker build --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% %BASE_IMAGE_ARG% -t windows-nano-far:%WINDOWS_VERSION% -t zippy1981/windows-nano-far:%WINDOWS_VERSION% "%~dp0."
