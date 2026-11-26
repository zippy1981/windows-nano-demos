@echo off
setlocal
pushd "%~dp0"
rem --memory 4g: Hyper-V isolated builds default to 1 GB and can hang during large zip extractions.
rem Stage any host DLLs the image needs into .\system32 here. This image currently needs none.
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2025
set BASE_IMAGE_ARG=
if not "%BASE_IMAGE%"=="" set BASE_IMAGE_ARG=--build-arg "BASE_IMAGE=%BASE_IMAGE%"
set DOTNET_SDK_VERSION_ARG=
if not "%DOTNET_SDK_VERSION%"=="" set DOTNET_SDK_VERSION_ARG=--build-arg "DOTNET_SDK_VERSION=%DOTNET_SDK_VERSION%"
set WIX_VERSION_ARG=
if not "%WIX_VERSION%"=="" set WIX_VERSION_ARG=--build-arg "WIX_VERSION=%WIX_VERSION%"
set GO_VERSION_ARG=
if not "%GO_VERSION%"=="" set GO_VERSION_ARG=--build-arg "GO_VERSION=%GO_VERSION%"
docker build --memory 4g --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% %BASE_IMAGE_ARG% %DOTNET_SDK_VERSION_ARG% %WIX_VERSION_ARG% %GO_VERSION_ARG% -t windows-nano-wix:%WINDOWS_VERSION% -t zippy1981/windows-nano-wix:%WINDOWS_VERSION% .
set BUILD_RESULT=%ERRORLEVEL%
popd
exit /b %BUILD_RESULT%
