@echo off
rem The gnu Rust toolchain, MinGit and micro are self-contained, so no host DLLs need to be staged in system32 right now.
rem Copy any host DLLs the image needs into .\system32 here.
if "%WINDOWS_VERSION%"=="" set WINDOWS_VERSION=2022
docker build --build-arg WINDOWS_VERSION=%WINDOWS_VERSION% -t windows-nano-rust:%WINDOWS_VERSION% -t zippy1981/windows-nano-rust:%WINDOWS_VERSION% .
