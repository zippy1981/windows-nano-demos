# PowerShell 7 with the Stackable SQLite ODBC driver on Nano Server

PowerShell 7 on Nano Server, with the [Stackable ODBC driver for SQLite](https://github.com/stackabletech/stackable-odbc-sqlite) installed system-wide. Any ODBC tool in the container can open a SQLite file (one `.db` file, no server to run) through the driver name `stackable_odbc_sqlite`. SQLite itself is compiled into the driver, so there is no separate SQLite to install.

It contains:

- PowerShell 7 from the base image, [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages/tree/main/images/nanoserver-base)'s `-pwsh` tag. The base also has bsdtar, `jq`, Microsoft Edit and the Visual C++ runtime.
- Stackable ODBC driver for SQLite 0.1.0, in `C:\Program Files\Stackable\ODBC`, registered system-wide under `HKLM\SOFTWARE\ODBC\ODBCINST.INI\stackable_odbc_sqlite`, so every user in the container can use it. Upstream's `configure-dsn.ps1` is next to the DLL, for creating data sources (DSNs).
- The Windows ODBC Driver Manager files Nano Server does not ship (`odbc32.dll`, `odbccp32.dll`, `odbcint.dll`, `odbcad32.exe` and `odbcconf.exe`), copied from a Server Core stage of the same Windows version. The driver itself imports `odbccp32.dll`, so without these copies nothing ODBC can even load on Nano Server.

All versions are pinned in the `Dockerfile`, and the driver download is checked against its pinned SHA-256.

## Running

```cmd
docker run -it --rm windows-nano-powershell-sqlite-odbc:2025
```

### With a database on a mounted volume

A SQLite database is a single file, so put it on a mounted volume and it outlives the container. Create a folder on the host, mount it at `C:\data`, and point the connection string (or a DSN) at a file there:

```cmd
mkdir data
docker run -it --rm -v "%CD%\data:C:\data" windows-nano-powershell-sqlite-odbc:2025
```

From PowerShell, the same mount with a one-off command:

```pwsh
docker run --rm -v "${PWD}\data:C:\data" windows-nano-powershell-sqlite-odbc:2025 pwsh -NoProfile -Command "Get-ChildItem C:\data"
```

Then connect from any ODBC tool with the DSN-less connection string below, using `Database=C:\data\my.db`. A file that does not exist yet is created on first connect. When the container is removed, `data\my.db` stays on the host, and the next container that mounts the same folder sees the same database.

## Connecting

Connection strings are `Key=Value` pairs joined by `;`, and the driver takes exactly one key:

| Key | Required | Meaning |
| --- | --- | --- |
| `Database` | Yes | Path to the SQLite file, or `:memory:` for a throwaway in-memory database |

```text
Driver=stackable_odbc_sqlite;Database=C:\data\my.db
```

A DSN is optional. To save one for the current user, run the script that ships with the driver (a System DSN, visible to every user, needs an administrator session):

```cmd
pwsh -File "C:\Program Files\Stackable\ODBC\configure-dsn.ps1" -NoGui -Set @{ DSN='mydata'; Database='C:\data\my.db' }
```

The driver's dialog for the ODBC Data Source Administrator is that same script; on Nano Server there is no desktop to show it in, so the `-NoGui` form above is the one to use.

## Building

To build a 2025 container, the default:

```cmd
build.cmd
```

To build another Windows version, from PowerShell:

```pwsh
$env:WINDOWS_VERSION=2022
./build.cmd
```

`WINDOWS_VERSION` can be 2019, 2022 or 2025. `build.cmd` passes `--memory 4g`, because Hyper-V's 1 GB default hangs builds. To build on a different base image, set `BASE_IMAGE` as well:

```cmd
set BASE_IMAGE=zippy1981/nanoserver-base:ltsc2025-pwsh
build.cmd
```

## Testing

`smoke-test.ps1 -Image <tag>` is what CI runs for 2019, 2022 and 2025 through the shared workflow. It checks the driver files and the system-wide (`HKLM`) registration, then runs `tests/smoke-odbc.ps1` inside the container. That script does real database work over ODBC, through the helper in `tests/OdbcSqlite.ps1`:

- in-memory (`Database=:memory:`): create a table, insert, update, delete and read back, and check that a second connection cannot see the first connection's table
- file (`Database=<file>`): create and insert in one connection, then read the rows back in a new connection, which proves the file was written

The longer test downloads a real US government database. It is not in CI, because it pulls about 79 MB:

```pwsh
./smoke-test-govdata.ps1 -Image windows-nano-powershell-sqlite-odbc:2025
```

That runs `tests/smoke-govdata.ps1` inside the container, which downloads the National Institute of Standards and Technology (NIST) [X-ray Properties Database in SQLite format](https://catalog.data.gov/dataset/x-ray-properties-database-in-sqlite-format) from `data.nist.gov`, checks the SQLite file header, and queries its `EDGE_ENERGIES`, `FFAST`, `LIT_REFERENCES` and `XRAY_ENERGIES` tables through the driver.

## Notes

- PowerShell 7 does not ship `System.Data.Odbc`, so the smoke tests call `odbc32.dll` directly from PowerShell. That also proves the Driver Manager, and not just the driver DLL, works on Nano Server.
- Foreign keys are enforced on every connection: the driver turns SQLite's `PRAGMA foreign_keys` on, which most other SQLite tooling leaves off.
