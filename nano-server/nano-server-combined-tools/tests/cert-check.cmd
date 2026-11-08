@echo off
rem Adds the fixture certificate to the machine root store with certoc and checks that the
rem store key with the fixture's SHA-1 thumbprint exists. Run as ContainerAdministrator
rem (smoke-test.ps1 does), because ContainerUser cannot write HKLM. Quoting a path with
rem spaces works inside a .cmd file, unlike a docker-run command string through cmd /S /C.
rem Usage: C:\tests\cert-check.cmd
setlocal
"C:\Program Files\combined-tools\certoc.exe" -addstore root C:\tests\fixtures\test.cer
if errorlevel 1 exit /b %ERRORLEVEL%
reg query HKLM\SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates\19E13843A8BF4B194E8E17F89DDBF7096E0D5BA7
exit /b %ERRORLEVEL%
