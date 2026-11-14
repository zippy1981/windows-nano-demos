<#
.SYNOPSIS
Longer smoke test for a built image: query a US government SQLite database over ODBC.
.DESCRIPTION
Runs tests/smoke-govdata.ps1 inside a throwaway container. That script downloads the National
Institute of Standards and Technology (NIST) X-ray Properties Database in SQLite format from
data.nist.gov (about 79 MB; the dataset is listed on data.gov), then opens it through the Stackable
ODBC driver and checks its tables and rows.

This is not part of the per-version CI smoke test, because of the download. Run it by hand against
a built image. Throws on the first failure.
.PARAMETER Image
The image to test.
.EXAMPLE
./nano-server/nano-server-powershell-sqlite-odbc/smoke-test-govdata.ps1 -Image windows-nano-powershell-sqlite-odbc:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

Write-Host "Govdata smoke testing $Image (downloads about 79 MB inside the container)"

# docker cp cannot touch a running Hyper-V container, so the container is created (not started),
# the scripts are copied in, and only then is it started with the test as its command.
$name = "powershell-sqlite-odbc-govdata-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
try {
    docker create --name $name $Image pwsh -NoLogo -NoProfile -File 'C:\smoke-govdata.ps1' | Out-Null
    if ($LASTEXITCODE) { throw 'creating the govdata container failed' }
    foreach ($script in 'OdbcSqlite.ps1', 'smoke-govdata.ps1') {
        docker cp (Join-Path $PSScriptRoot "tests/$script") "${name}:C:/$script" | Out-Null
        if ($LASTEXITCODE) { throw "docker cp of $script failed" }
    }
    docker start -a $name | Out-Host
    $code = docker inspect -f '{{.State.ExitCode}}' $name
    if ($code -ne '0') { throw "smoke-govdata.ps1 failed: container exit code $code" }
}
finally {
    docker rm -f $name 2>$null | Out-Null
}
Write-Host 'govdata smoke test passed'
