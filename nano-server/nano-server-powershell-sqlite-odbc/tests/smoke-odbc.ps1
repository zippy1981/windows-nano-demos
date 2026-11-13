<#
.SYNOPSIS
Smoke test that runs inside the windows-nano-powershell-sqlite-odbc image: basic SQLite work over ODBC.
.DESCRIPTION
Exercises the Stackable driver the way a user would, with DSN-less connection strings from the upstream
documentation (Driver=stackable_odbc_sqlite;Database=<path or :memory:>):

- an in-memory database: create a table, insert, update, delete and read the rows back, all on one
  connection (an in-memory database is per-connection, so a second connection must not see it)
- a file database: the same create and insert, then a second connection that must still see the rows,
  which proves the file was really written

Throws on the first failure. smoke-test.ps1 copies this file and OdbcSqlite.ps1 into a container and
runs it there.
.EXAMPLE
./tests/smoke-odbc.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'OdbcSqlite.ps1')

function Assert-Equal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$What
    )
    if ($Actual -ne $Expected) { throw "$What`: expected '$Expected', got '$Actual'" }
    Write-Output "ok: $What = $Actual"
}

# The driver is registered system-wide, so this connection works for ContainerUser with no DSN and
# no per-user setup. :memory: is the driver's documented throwaway database.
$memory = 'Driver=stackable_odbc_sqlite;Database=:memory:'
$conn = Open-OdbcSqlite -ConnectionString $memory
try {
    Invoke-OdbcSql -Connection $conn -Sql 'CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, qty INTEGER NOT NULL)' | Out-Null
    Invoke-OdbcSql -Connection $conn -Sql "INSERT INTO items (id, name, qty) VALUES (1, 'apple', 3)" | Out-Null
    Invoke-OdbcSql -Connection $conn -Sql "INSERT INTO items (id, name, qty) VALUES (2, 'pear', 5)" | Out-Null
    Invoke-OdbcSql -Connection $conn -Sql "INSERT INTO items (id, name, qty) VALUES (3, 'plum', 7)" | Out-Null
    Assert-Equal -What 'in-memory row count' -Expected '3' -Actual (Invoke-OdbcSql -Connection $conn -Sql 'SELECT COUNT(*) FROM items')
    Assert-Equal -What 'in-memory read back' -Expected 'pear|5' -Actual (Invoke-OdbcSql -Connection $conn -Sql 'SELECT name, qty FROM items WHERE id = 2')
    Invoke-OdbcSql -Connection $conn -Sql 'UPDATE items SET qty = 6 WHERE id = 2' | Out-Null
    Assert-Equal -What 'in-memory update' -Expected '6' -Actual (Invoke-OdbcSql -Connection $conn -Sql 'SELECT qty FROM items WHERE id = 2')
    Invoke-OdbcSql -Connection $conn -Sql 'DELETE FROM items WHERE id = 3' | Out-Null
    Assert-Equal -What 'in-memory delete' -Expected '2' -Actual (Invoke-OdbcSql -Connection $conn -Sql 'SELECT COUNT(*) FROM items')
}
finally {
    Close-OdbcSqlite -Connection $conn
}
# An in-memory database is per-connection, so a new connection must not see the table above.
$other = Open-OdbcSqlite -ConnectionString $memory
try {
    $leaked = $true
    try { Invoke-OdbcSql -Connection $other -Sql 'SELECT COUNT(*) FROM items' | Out-Null } catch { $leaked = $false }
    if ($leaked) { throw 'a second :memory: connection saw the first connection''s table' }
    Write-Output 'ok: :memory: databases are per-connection'
}
finally {
    Close-OdbcSqlite -Connection $other
}

# A file database: write in one connection, read the rows back in a new one.
$dir = Join-Path $HOME "odbc-smoke-$PID"
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $database = Join-Path $dir 'smoke.db'
    $file = "Driver=stackable_odbc_sqlite;Database=$database"
    $writer = Open-OdbcSqlite -ConnectionString $file
    try {
        Invoke-OdbcSql -Connection $writer -Sql 'CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL, qty INTEGER NOT NULL)' | Out-Null
        Invoke-OdbcSql -Connection $writer -Sql "INSERT INTO items (id, name, qty) VALUES (1, 'apple', 3)" | Out-Null
    }
    finally {
        Close-OdbcSqlite -Connection $writer
    }
    if (-not (Test-Path $database)) { throw "the driver did not create $database" }
    if ((Get-Item $database).Length -lt 1) { throw "$database is empty" }
    Write-Output "ok: file database created at $database"
    $reader = Open-OdbcSqlite -ConnectionString $file
    try {
        Assert-Equal -What 'file read back in a new connection' -Expected 'apple|3' -Actual (Invoke-OdbcSql -Connection $reader -Sql 'SELECT name, qty FROM items WHERE id = 1')
    }
    finally {
        Close-OdbcSqlite -Connection $reader
    }
}
finally {
    try { Remove-Item -Recurse -Force $dir } catch { Write-Warning "Cleanup of $dir failed: $_" }
}

Write-Output 'SMOKE TEST PASSED'
