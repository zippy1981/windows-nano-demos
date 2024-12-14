Copy-Item $env:SystemRoot\\system32\\vcruntime140.dll .\system32
if (Test-Path "C:\Program Files\7-Zip") {
    Copy-Item "C:\Program Files\7-Zip\7z.exe" .\system32
    Copy-Item "C:\Program Files\7-Zip\7z.dll" .\system32
}

$jq_url = (Invoke-RestMethod https://api.github.com/repos/jqlang/jq/releases/latest | Select-Object -ExpandProperty assets| Where-Object name -eq jq-windows-amd64.exe).browser_download_url
curl $jq_url -L --clobber -o system32\jq.exe

docker build --build-arg WINDOWS_VERSION=$env:WINDOWS_VERSION  -t "windows-nano-php:$env:WINDOWS_VERSION" -t "zippy1981/windows-nano-php:$env:WINDOWS_VERSION" .
