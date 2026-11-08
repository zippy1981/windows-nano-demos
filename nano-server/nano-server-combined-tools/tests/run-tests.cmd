@echo off
rem Tests for the combined tools in this image. Writes TAP to stdout and exits with the number of failures.
rem Uses only cmd built-ins, nanoserver's own findstr and reg for the checks, so a broken tool cannot
rem hide its own failure. Usage: C:\tests\run-tests.cmd
setlocal
set FIX=C:\tests\fixtures
set WORK=C:\work
set "CT=C:\Program Files\combined-tools"
set OUT=%WORK%\test-out.txt
set T=0
set FAILS=0
if not exist "%WORK%" mkdir "%WORK%"

rem Wine-sourced tools (the manifest defaults overlaps to Wine).
set "D=1 find in a file (wine)"& set "RX=^one"& set RXI=
find "one" %FIX%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=2 fc reports differences (wine)"& set "RX=Comparing files"& set RXI=
fc %FIX%\a.txt %FIX%\b.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 1

set "D=3 where finds cmd (wine)"& set "RX=\\cmd\.exe$"& set RXI=/i
where cmd > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=4 whoami (wine)"& set "RX=\\ContainerUser"& set RXI=/i
whoami > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=5 tasklist lists processes (wine)"& set "RX=cmd\.exe"& set RXI=/i
tasklist > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

rem ReactOS-sourced tools (unique to ReactOS in this set, so they exercise the shim).
set "D=6 more pipes through (reactos)"& set "RX=^one"& set RXI=
type %FIX%\a.txt | more > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=7 tree /f lists fixtures (reactos)"& set "RX=a\.txt"& set RXI=
tree /f %FIX% > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=8 comp on identical files (reactos)"& set "RX=compare OK"& set RXI=/i
echo n| comp %FIX%\a.txt %FIX%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=9 nslookup resolves localhost (reactos)"& set "RX=127\.0\.0\.1"& set RXI=
nslookup localhost > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

rem Certificate support: certoc from Server Core adds the test certificate to the root store.
rem The smoke test runs as ContainerUser, who cannot write HKLM, so this check only verifies
rem that certoc loads and prints usage. smoke-test.ps1 runs the real add-store check
rem as ContainerAdministrator, because ContainerUser cannot write the machine store.
set "D=10 certoc loads (servercore)"& set RX=& set RXI=
"%CT%\certoc.exe" -? > "%OUT%" 2>&1
set RC=%ERRORLEVEL%
if "%RC%"=="-1073741511" goto certbad
if "%RC%"=="-1073741515" goto certbad
if "%RC%"=="-1073741819" goto certbad
set /a T+=1
echo ok %T% - %D% (exit %RC%)
goto certdone
:certbad
set /a T+=1
set /a FAILS+=1
echo not ok %T% - %D% (exit %RC%)
call :dump
:certdone

rem Every selected tool loads. 0xC0000139, 0xC0000135 and 0xC0000005 are the loader failures.
for /f "usebackq eol=# tokens=1 delims==" %%t in ("C:\tests\tool-sources.txt") do call :loadcheck %%t

echo 1..%T%
echo # %FAILS% failure(s)
if exist "%OUT%" del "%OUT%"
exit /b %FAILS%

:loadcheck
if "%~1"=="#" goto :eof
set "D=11 %~1 loads"& set RX=& set RXI=
"%CT%\%~1" /? > "%OUT%" 2>&1
set RC=%ERRORLEVEL%
if "%RC%"=="-1073741511" goto loadbad
if "%RC%"=="-1073741515" goto loadbad
if "%RC%"=="-1073741819" goto loadbad
set /a T+=1
echo ok %T% - %D% (exit %RC%)
goto :eof
:loadbad
set /a T+=1
set /a FAILS+=1
echo not ok %T% - %D% (exit %RC%)
call :dump
goto :eof

:check
set /a T+=1
set RC=%~1
if not "%RC%"=="%~2" goto checkbad
if not defined RX goto checkok
findstr %RXI% /r /c:"%RX%" "%OUT%" > NUL
if errorlevel 1 goto checkbad
:checkok
echo ok %T% - %D%
goto :eof
:checkbad
set /a FAILS+=1
echo not ok %T% - %D% (exit %RC%, expected %~2; regex "%RX%")
call :dump
goto :eof

:dump
if not exist "%OUT%" goto :eof
for /f "usebackq delims=" %%l in ("%OUT%") do echo #   %%l
goto :eof
