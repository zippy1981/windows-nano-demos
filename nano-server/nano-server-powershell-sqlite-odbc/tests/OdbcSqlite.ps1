<#
.SYNOPSIS
Runs SQL against SQLite through the Stackable ODBC driver, for the smoke tests in this folder.
.DESCRIPTION
Dot-source this file, open a connection with Open-OdbcSqlite, run statements with Invoke-OdbcSql, and
close it with Close-OdbcSqlite. Invoke-OdbcSql returns one string per result row, with the columns
joined by '|'; a statement with no result set returns nothing. A connection is a real ODBC connection,
so an in-memory (Database=:memory:) database lives exactly as long as its connection does.

PowerShell 7 does not ship System.Data.Odbc, so the helper calls the ODBC Driver Manager (odbc32.dll)
directly. That is also what the smoke tests are proving works on Nano Server: the Driver Manager loads
stackable_odbc_sqlite, and the driver runs the SQL against the file (or :memory:) in the connection string.
.EXAMPLE
. ./OdbcSqlite.ps1
$conn = Open-OdbcSqlite -ConnectionString 'Driver=stackable_odbc_sqlite;Database=:memory:'
Invoke-OdbcSql -Connection $conn -Sql 'SELECT 1'
Close-OdbcSqlite -Connection $conn
#>
[CmdletBinding()]
param()

if (-not ('OdbcSqliteConnection' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class OdbcSqliteConnection : IDisposable
{
    private const short SqlHandleEnv = 1;
    private const short SqlHandleDbc = 2;
    private const short SqlHandleStmt = 3;
    private const short SqlSuccess = 0;
    private const short SqlSuccessWithInfo = 1;
    private const short SqlNoData = 100;
    private const int SqlNts = -3;
    private const short SqlCWideChar = -8;
    private const int SqlAttrOdbcVersion = 200;
    private static readonly IntPtr SqlOdbcVersion3 = new IntPtr(3);

    [DllImport("odbc32.dll", CharSet = CharSet.Unicode)]
    private static extern short SQLAllocHandle(short handleType, IntPtr inputHandle, out IntPtr outputHandle);

    [DllImport("odbc32.dll")]
    private static extern short SQLSetEnvAttr(IntPtr environment, int attribute, IntPtr value, int stringLength);

    [DllImport("odbc32.dll", CharSet = CharSet.Unicode)]
    private static extern short SQLDriverConnect(IntPtr connection, IntPtr window, string inConnectionString,
        short inLength, StringBuilder outConnectionString, short outCapacity, out short outLength, ushort flags);

    [DllImport("odbc32.dll", CharSet = CharSet.Unicode)]
    private static extern short SQLExecDirect(IntPtr statement, string sql, int length);

    [DllImport("odbc32.dll")]
    private static extern short SQLFetch(IntPtr statement);

    [DllImport("odbc32.dll", CharSet = CharSet.Unicode)]
    private static extern short SQLGetData(IntPtr statement, ushort column, short targetType,
        StringBuilder buffer, int bufferLength, out IntPtr indicator);

    [DllImport("odbc32.dll")]
    private static extern short SQLNumResultCols(IntPtr statement, out short columns);

    [DllImport("odbc32.dll")]
    private static extern short SQLDisconnect(IntPtr connection);

    [DllImport("odbc32.dll")]
    private static extern short SQLFreeHandle(short handleType, IntPtr handle);

    [DllImport("odbc32.dll", CharSet = CharSet.Unicode)]
    private static extern short SQLGetDiagRec(short handleType, IntPtr handle, short record,
        StringBuilder state, out int nativeError, StringBuilder message, short messageCapacity, out short messageLength);

    private IntPtr env = IntPtr.Zero;
    private IntPtr dbc = IntPtr.Zero;

    private static bool Ok(short rc) { return rc == SqlSuccess || rc == SqlSuccessWithInfo; }

    private static void Check(short rc, short handleType, IntPtr handle, string what)
    {
        if (Ok(rc) || rc == SqlNoData) { return; }
        var state = new StringBuilder(16);
        var message = new StringBuilder(1024);
        int native;
        short messageLength;
        string detail = "";
        if (handle != IntPtr.Zero &&
            SQLGetDiagRec(handleType, handle, 1, state, out native, message, (short)message.Capacity, out messageLength) == SqlSuccess)
        {
            detail = " [" + state + "] " + message;
        }
        throw new InvalidOperationException(what + " failed with ODBC return code " + rc + "." + detail);
    }

    public void Open(string connectionString)
    {
        Check(SQLAllocHandle(SqlHandleEnv, IntPtr.Zero, out env), SqlHandleEnv, env, "SQLAllocHandle(ENV)");
        Check(SQLSetEnvAttr(env, SqlAttrOdbcVersion, SqlOdbcVersion3, 0), SqlHandleEnv, env, "SQLSetEnvAttr");
        Check(SQLAllocHandle(SqlHandleDbc, env, out dbc), SqlHandleDbc, dbc, "SQLAllocHandle(DBC)");
        var connected = new StringBuilder(1024);
        short connectedLength;
        Check(SQLDriverConnect(dbc, IntPtr.Zero, connectionString, SqlNts, connected, (short)connected.Capacity,
            out connectedLength, 0), SqlHandleDbc, dbc, "SQLDriverConnect(" + connectionString + ")");
    }

    public string[] Query(string sql)
    {
        IntPtr stmt = IntPtr.Zero;
        try
        {
            Check(SQLAllocHandle(SqlHandleStmt, dbc, out stmt), SqlHandleStmt, stmt, "SQLAllocHandle(STMT)");
            Check(SQLExecDirect(stmt, sql, SqlNts), SqlHandleStmt, stmt, "SQLExecDirect(" + sql + ")");
            short columns;
            Check(SQLNumResultCols(stmt, out columns), SqlHandleStmt, stmt, "SQLNumResultCols");
            var rows = new List<string>();
            if (columns < 1) { return rows.ToArray(); }
            while (true)
            {
                short fetched = SQLFetch(stmt);
                if (fetched == SqlNoData) { break; }
                Check(fetched, SqlHandleStmt, stmt, "SQLFetch");
                var cells = new string[columns];
                for (ushort column = 1; column <= columns; column++)
                {
                    var buffer = new StringBuilder(2048);
                    IntPtr indicator;
                    short got = SQLGetData(stmt, column, SqlCWideChar, buffer, buffer.Capacity * 2, out indicator);
                    Check(got, SqlHandleStmt, stmt, "SQLGetData");
                    cells[column - 1] = indicator == new IntPtr(-1) ? "" : buffer.ToString();
                }
                rows.Add(String.Join("|", cells));
            }
            return rows.ToArray();
        }
        finally
        {
            if (stmt != IntPtr.Zero) { SQLFreeHandle(SqlHandleStmt, stmt); }
        }
    }

    public void Dispose()
    {
        if (dbc != IntPtr.Zero) { SQLDisconnect(dbc); SQLFreeHandle(SqlHandleDbc, dbc); dbc = IntPtr.Zero; }
        if (env != IntPtr.Zero) { SQLFreeHandle(SqlHandleEnv, env); env = IntPtr.Zero; }
    }
}
'@
}

function Open-OdbcSqlite {
    <#
    .SYNOPSIS
    Opens an ODBC connection to SQLite through the Stackable driver.
    #>
    [CmdletBinding()]
    [OutputType([OdbcSqliteConnection])]
    param(
        [Parameter(Mandatory)][string]$ConnectionString
    )
    $connection = [OdbcSqliteConnection]::new()
    $connection.Open($ConnectionString)
    $connection
}

function Invoke-OdbcSql {
    <#
    .SYNOPSIS
    Runs one SQL statement on an open OdbcSqlite connection and returns its rows.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][OdbcSqliteConnection]$Connection,
        [Parameter(Mandatory)][string]$Sql
    )
    $Connection.Query($Sql)
}

function Close-OdbcSqlite {
    <#
    .SYNOPSIS
    Closes an OdbcSqlite connection opened with Open-OdbcSqlite.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][OdbcSqliteConnection]$Connection
    )
    $Connection.Dispose()
}
