<#
.SYNOPSIS
Longer smoke test that runs inside the image: query a US government SQLite database over ODBC.
.DESCRIPTION
Downloads the National Institute of Standards and Technology (NIST) X-ray Properties Database in
SQLite format from data.nist.gov (listed on data.gov as "X-ray Properties Database in SQLite
Format"), checks that the download really is a SQLite file, then opens it through the Stackable
ODBC driver and checks its tables and rows.

This downloads about 79 MB, so it is not part of the per-version CI smoke test. Run it through
smoke-test-govdata.ps1 on the host. Throws on the first failure.
.EXAMPLE
./tests/smoke-govdata.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'OdbcSqlite.ps1')

function Assert-True {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$What
    )
    if (-not $Condition) { throw $What }
    Write-Output "ok: $What"
}

$dir = Join-Path $HOME "odbc-govdata-$PID"
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $database = Join-Path $dir 'atomic_database.db'
    $url = 'https://data.nist.gov/od/ds/mds2-2819/atomic_database.db'
    Write-Output "downloading $url"
    curl.exe -fsSLo $database $url
    if ($LASTEXITCODE) { throw "downloading the NIST database failed: $LASTEXITCODE" }
    $size = (Get-Item $database).Length
    Assert-True -Condition ($size -gt 10MB) -What "NIST database downloaded ($size bytes)"
    $header = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($database)[0..14])
    Assert-True -Condition ($header -eq 'SQLite format 3') -What 'download starts with the SQLite file header'

    $conn = Open-OdbcSqlite -ConnectionString "Driver=stackable_odbc_sqlite;Database=$database"
    try {
        $tables = @(Invoke-OdbcSql -Connection $conn -Sql "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        Write-Output "tables: $($tables -join ', ')"
        foreach ($table in 'EDGE_ENERGIES', 'FFAST', 'LIT_REFERENCES', 'XRAY_ENERGIES') {
            Assert-True -Condition ($tables -contains $table) -What "database has the $table table"
        }
        $edges = [int](Invoke-OdbcSql -Connection $conn -Sql 'SELECT COUNT(*) FROM EDGE_ENERGIES')
        Assert-True -Condition ($edges -gt 1000) -What "EDGE_ENERGIES has $edges rows"
        $iron = [int](Invoke-OdbcSql -Connection $conn -Sql 'SELECT COUNT(*) FROM EDGE_ENERGIES WHERE Z = 26')
        Assert-True -Condition ($iron -gt 0) -What "EDGE_ENERGIES has $iron rows for iron (Z = 26)"
        $row = Invoke-OdbcSql -Connection $conn -Sql 'SELECT Subshell FROM EDGE_ENERGIES WHERE Z = 26 ORDER BY Energy LIMIT 1'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($row)) -What "read a subshell for iron: $row"
    }
    finally {
        Close-OdbcSqlite -Connection $conn
    }
}
finally {
    try { Remove-Item -Recurse -Force $dir } catch { Write-Warning "Cleanup of $dir failed: $_" }
}

Write-Output 'GOVDATA SMOKE TEST PASSED'
