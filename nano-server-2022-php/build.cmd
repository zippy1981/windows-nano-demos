@echo off
copy %SYSTEMROOT%\\system32\\vcruntime140.dll .\system32
COPY "C:\Program Files\7-Zip\7z.exe" .\system32
COPY "C:\Program Files\7-Zip\7z.dll" .\system32
docker build -t windows-nano-php .
