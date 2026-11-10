<#
.SYNOPSIS
Pester tests for Test-ContainerHost.ps1.
.DESCRIPTION
Mocks docker, CIM, Windows features, drives and web requests, so the tests change nothing and need no network.
.EXAMPLE
Invoke-Pester -Path ./scripts/Test-ContainerHost.Tests.ps1
#>
[CmdletBinding()]
param()

BeforeAll {
    $script:checker = Join-Path $PSScriptRoot 'Test-ContainerHost.ps1'

    function Invoke-Checker {
        param([hashtable]$Parameters = @{})
        $json = & $script:checker -Json -Root $script:root @Parameters
        $script:exitCode = $LASTEXITCODE
        @($json | ConvertFrom-Json)
    }

    function Get-Row {
        param([object[]]$Rows, [string]$Check)
        $Rows | Where-Object Check -EQ $Check
    }

    # Mocks run in another scope, so the docker info they return travels in an environment variable
    function Use-DockerInfo {
        param([hashtable]$Changes = @{})
        $info = @{ OSType = 'windows'; Isolation = 'hyperv'; ServerVersion = '29.9.3'; DockerRootDir = 'C:\ProgramData\docker' }
        foreach ($key in $Changes.Keys) { $info[$key] = $Changes[$key] }
        $env:CONTAINER_HOST_TEST_DOCKER_INFO = $info | ConvertTo-Json -Compress
    }
}

Describe 'Test-ContainerHost' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $script:root 'nano-server/nano-server-x')
        $global:LASTEXITCODE = 0
        Use-DockerInfo
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Windows 11 Pro'; BuildNumber = '26100'; ProductType = 1 } }
        Mock docker { $global:LASTEXITCODE = 0; $env:CONTAINER_HOST_TEST_DOCKER_INFO }
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = 'Enabled' } }
        Mock Get-PSDrive { [pscustomobject]@{ Free = 100GB } }
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
    }

    AfterEach {
        Remove-Item -Path Env:CONTAINER_HOST_TEST_DOCKER_INFO -ErrorAction SilentlyContinue
    }

    It 'passes a healthy host' {
        $rows = Invoke-Checker
        $rows.Status | Sort-Object -Unique | Should -Be 'pass'
        $script:exitCode | Should -Be 0
        (Get-Row $rows 'OS').Evidence | Should -Match 'client: Hyper-V isolation'
        (Get-Row $rows 'build.cmd host files').Evidence | Should -Be 'no build.cmd copies host files'
    }

    It 'fails when docker is not running' {
        Mock docker { $global:LASTEXITCODE = 1 }
        $rows = Invoke-Checker
        (Get-Row $rows 'Docker engine').Status | Should -Be 'fail'
        Get-Row $rows 'Disk' | Should -BeNullOrEmpty
        $script:exitCode | Should -Be 1
    }

    It 'fails a Linux-mode engine and says how to switch' {
        Use-DockerInfo @{ OSType = 'linux' }
        $row = Get-Row (Invoke-Checker) 'Docker engine'
        $row.Status | Should -Be 'fail'
        $row.Fix | Should -Match 'SwitchWindowsEngine'
    }

    It 'warns when features need elevation and fails a disabled one' {
        Mock Get-WindowsOptionalFeature { throw 'The requested operation requires elevation.' } -ParameterFilter { $FeatureName -eq 'Containers' }
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = 'Disabled' } } -ParameterFilter { $FeatureName -eq 'Microsoft-Hyper-V-All' }
        $rows = Invoke-Checker
        (Get-Row $rows 'Feature Containers').Status | Should -Be 'warn'
        (Get-Row $rows 'Feature Microsoft-Hyper-V-All').Fix | Should -Match 'Enable-WindowsOptionalFeature'
    }

    It 'flags bases newer than the host and process isolation mismatches' {
        Mock Get-CimInstance { [pscustomobject]@{ Caption = 'Windows Server 2022'; BuildNumber = '20348'; ProductType = 3 } }
        Use-DockerInfo @{ Isolation = 'process' }
        $rows = Invoke-Checker
        (Get-Row $rows 'Base ltsc2019 (17763)').Status | Should -Be 'warn'
        (Get-Row $rows 'Base ltsc2022 (20348)').Status | Should -Be 'pass'
        (Get-Row $rows 'Base ltsc2025 (26100)').Status | Should -Be 'fail'
        (Get-Row $rows 'OS').Evidence | Should -Match 'server'
    }

    It 'grades free disk space' -TestCases @(
        @{ Free = 10GB; Status = 'fail' }
        @{ Free = 30GB; Status = 'warn' }
        @{ Free = 50GB; Status = 'pass' }
    ) {
        Mock Get-PSDrive { [pscustomobject]@{ Free = $Free } }
        (Get-Row (Invoke-Checker) 'Disk').Status | Should -Be $Status
    }

    It 'warns about host files a build.cmd copies that are missing' {
        $present = Join-Path $TestDrive 'present.dll'
        Set-Content -LiteralPath $present -Value 'x'
        $lines = "@echo off`r`nrem copy C:\ignored\comment.dll .`r`ncopy `"$present`" system32\`r`ncopy C:\definitely\missing.dll system32\`r`n"
        Set-Content -LiteralPath (Join-Path $script:root 'nano-server/nano-server-x/build.cmd') -Value $lines -NoNewline
        $row = Get-Row (Invoke-Checker) 'build.cmd host files'
        $row.Status | Should -Be 'warn'
        $row.Evidence | Should -Be 'nano-server-x: C:\definitely\missing.dll'
    }

    It 'counts host files that are present' {
        $present = Join-Path $TestDrive 'present.dll'
        Set-Content -LiteralPath $present -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:root 'nano-server/nano-server-x/build.cmd') -Value "copy `"$present`" system32\"
        (Get-Row (Invoke-Checker) 'build.cmd host files').Evidence | Should -Be '1 host files present'
    }

    It 'fails an unreachable download host' {
        Mock Invoke-WebRequest { throw 'No such host is known.' } -ParameterFilter { $Uri -eq 'https://nodejs.org' }
        $rows = Invoke-Checker
        (Get-Row $rows 'Network https://nodejs.org').Status | Should -Be 'fail'
        (Get-Row $rows 'Network https://github.com').Status | Should -Be 'pass'
    }

    It 'skips the network with -SkipNetwork' {
        $rows = Invoke-Checker @{ SkipNetwork = $true }
        $rows.Check | Should -Not -Contain 'Network https://github.com'
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'prints a table without -Json' {
        $text = & $script:checker -Root $script:root -SkipNetwork
        "$text" | Should -Match 'Check\s+Status\s+Evidence'
    }
}
