@echo off
rem Tests for the ReactOS tools in this image. Writes TAP to stdout and exits with the number of failures.
rem Uses only cmd built-ins and nanoserver's own findstr for the checks, so a broken ReactOS tool cannot
rem hide its own failure. Test numbers match the test plan in plans/reactos-binaries.md.
rem Usage: C:\tests\run-tests.cmd
setlocal
set FIX=C:\tests\fixtures
set WORK=C:\work
set "RT=C:\tools\reactos"
set OUT=%WORK%\test-out.txt
set T=0
set FAILS=0
if not exist "%WORK%" mkdir "%WORK%"
rem ReactOS find only handled a relative file name in the prototype, so run from the fixtures folder.
cd /d %FIX%

rem ReactOS find skips files with the offline attribute, which docker-copied fixtures can carry,
rem so search a copy made inside the container (the same reason test 19 builds its file in C:\work).
copy /y %FIX%\a.txt %WORK%\a.txt > NUL
set "D=1 find in a file"& set "RX=^one"& set RXI=
"%RT%\find.exe" "one" %WORK%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=2 find /c counts matches"& set "RX=^1$"& set RXI=
type %FIX%\a.txt | find /c "one" > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=3 more pipes through"& set "RX=^one"& set RXI=
type %FIX%\a.txt | more > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=4 fc reports differences"& set "RX=Comparing files"& set RXI=
fc %FIX%\a.txt %FIX%\b.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 1

set "D=5 fc on identical files"& set "RX=no differences"& set RXI=/i
fc %FIX%\a.txt %FIX%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=6 where finds cmd"& set "RX=\\cmd\.exe$"& set RXI=/i
where cmd > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=7 whoami"& set "RX=\\containeruser$"& set RXI=/i
whoami > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=8 tree /f lists fixtures"& set "RX=a\.txt"& set RXI=
tree /f %FIX% > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=9 comp on identical files"& set "RX=compare OK"& set RXI=/i
echo n| comp %FIX%\a.txt %FIX%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=10 tasklist lists processes"& set "RX=cmd\.exe"& set RXI=/i
tasklist > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=11 taskkill prints usage"& set "RX=taskkill"& set RXI=/i
taskkill /? > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=12 chcp prints the code page"& set "RX=code page"& set RXI=/i
chcp > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=13 mode con prints status"& set "RX=CON"& set RXI=
mode con > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

rem ReactOS help prints the help but exits 1.
set "D=14 help dir prints help"& set "RX=DIR"& set RXI=
help dir > "%OUT%" 2>&1
call :check %ERRORLEVEL% 1

set "D=15 replace prints usage"& set "RX=REPLACE"& set RXI=/i
replace /? > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=16 fsutil lists drives"& set "RX=Drives:"& set RXI=
fsutil fsinfo drives > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=17 nslookup resolves localhost"& set "RX=127\.0\.0\.1"& set RXI=
nslookup localhost > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

set "D=18 cacls lists a file"& set "RX=a\.txt"& set RXI=/i
cacls %FIX%\a.txt > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

rem 19: stack-probe check. A tool with a frame over 4 KiB exercises __chkstk in the shim.
if exist "%WORK%\big.txt" del "%WORK%\big.txt"
for /l %%i in (1,1,20000) do echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx >> "%WORK%\big.txt"
set "D=19 find /c on a large file (shim __chkstk)"& set "RX=20000$"& set RXI=
find /c "x" "%WORK%\big.txt" > "%OUT%" 2>&1
call :check %ERRORLEVEL% 0

rem 20: every tool loads. 0xC0000139 entry point not found, 0xC0000135 DLL not found, 0xC0000005 access violation.
for /f "usebackq eol=# tokens=* delims=" %%t in ("C:\tests\tools.txt") do call :loadcheck %%t

echo 1..%T%
echo # %FAILS% failure(s)
if exist "%OUT%" del "%OUT%"
exit /b %FAILS%

:loadcheck
set "D=20 %~1 loads"& set RX=& set RXI=
"%RT%\%~1" /? > "%OUT%" 2>&1
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
