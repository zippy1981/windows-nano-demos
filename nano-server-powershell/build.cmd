@echo off
setlocal
pushd "%~dp0"
REM Stage any host DLLs the image needs into .\system32 here. PowerShell, MinGit and micro currently need none.
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2022
set BASE_IMAGE_ARG=
if not "%BASE_IMAGE%"=="" set BASE_IMAGE_ARG=--build-arg "BASE_IMAGE=%BASE_IMAGE%"
docker build --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% %BASE_IMAGE_ARG% -t windows-nano-powershell:%WINDOWS_VERSION% -t zippy1981/windows-nano-powershell:%WINDOWS_VERSION% .
set BUILD_RESULT=%ERRORLEVEL%
popd
exit /b %BUILD_RESULT%
