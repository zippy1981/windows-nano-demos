<#
.SYNOPSIS
Pester tests for New-NanoServerImage.ps1.
.DESCRIPTION
Scaffolds images into $TestDrive and checks the generated Dockerfile, build.cmd and README against the
repository conventions. The tests do not touch the real nano-server folder.
.EXAMPLE
Invoke-Pester -Path ./scripts/New-NanoServerImage.Tests.ps1
#>
[CmdletBinding()]
param()

BeforeAll {
    $script:generator = Join-Path $PSScriptRoot 'New-NanoServerImage.ps1'

    function Invoke-Generator {
        param(
            [hashtable]$Parameters,
            [switch]$Force,
            [switch]$WhatIf
        )
        $arguments = $Parameters.Clone()
        if ($Force) { $arguments['Force'] = $true }
        if ($WhatIf) { $arguments['WhatIf'] = $true }
        & $script:generator @arguments
    }

    function Get-GeneratedText {
        param(
            [string]$Name,
            [string]$File
        )
        $path = Join-Path $script:root "nano-server/nano-server-$Name/$File"
        [System.IO.File]::ReadAllText($path)
    }
}

Describe 'New-NanoServerImage validation' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'rejects <Name>' -TestCases @(
        @{ Name = 'BadName' }
        @{ Name = 'bad_name' }
        @{ Name = 'bad--name' }
        @{ Name = '-bad' }
        @{ Name = 'bad-' }
    ) {
        { Invoke-Generator -Parameters @{ Name = $Name; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root } } |
            Should -Throw
    }

    It 'rejects a version string that is not in the URL' {
        { Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; VersionString = '9.9.9'; RepositoryRoot = $script:root } } |
            Should -Throw -ExpectedMessage '*not in Url*'
    }
}

Describe 'New-NanoServerImage scaffold' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'creates the standard files and returns their paths' {
        $result = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }

        $result.Name | Should -Be 'tool'
        $result.Image | Should -Be 'windows-nano-tool'
        $result.Folder | Should -Be (Join-Path $script:root 'nano-server/nano-server-tool')
        $result.Dockerfile | Should -Be (Join-Path $result.Folder 'Dockerfile')
        $result.BuildScript | Should -Be (Join-Path $result.Folder 'build.cmd')
        $result.Readme | Should -Be (Join-Path $result.Folder 'README.md')
        Test-Path -LiteralPath $result.Dockerfile | Should -BeTrue
        Test-Path -LiteralPath $result.BuildScript | Should -BeTrue
        Test-Path -LiteralPath $result.Readme | Should -BeTrue
    }

    It 'uses a placeholder URL when -Url is omitted' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile
        $dockerfile | Should -BeLike '*https://example.com/download/artifact.zip*'
    }

    It 'writes a Dockerfile with the standard base arguments' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile

        $dockerfile | Should -BeLike '*ARG WINDOWS_VERSION=2025*'
        $dockerfile | Should -BeLike '*# Docker Hub categories: developer-tools*'
        $dockerfile | Should -BeLike '*ARG BASE_IMAGE=mcr.microsoft.com/windows/nanoserver:ltsc${WINDOWS_VERSION}-amd64*'
        $dockerfile | Should -BeLike '*FROM ${BASE_IMAGE}*'
        $dockerfile | Should -BeLike '*RUN mkdir "%TOOL_DIR%"*'
        $dockerfile | Should -BeLike '*curl -fLo "C:\tool.zip" "https://example.com/tool.zip"*'
        $dockerfile | Should -BeLike '*tar.exe -xf C:\tool.zip -C "%TOOL_DIR%"*'
        $dockerfile | Should -BeLike '*tar.exe is part of Nano Server*'
        $dockerfile | Should -BeLike '*setx PATH "%TOOL_DIR%"*'
        $dockerfile | Should -BeLike '*WORKDIR C:/users/containeruser*'
        $dockerfile | Should -Match ([regex]::Escape('ENTRYPOINT ["cmd", "/S", "/C"]'))
        $dockerfile | Should -Not -BeLike '*TOOL_VERSION*'
    }

    It 'writes build.cmd with the memory limit and both image names' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $build = Get-GeneratedText -Name tool -File build.cmd

        $build | Should -BeLike '*--build-arg WINDOWS_VERSION=%WINDOWS_VERSION%*'
        $build | Should -BeLike '*--memory 4g*'
        $build | Should -BeLike '*-t windows-nano-tool:%WINDOWS_VERSION%*'
        $build | Should -BeLike '*-t zippy1981/windows-nano-tool:%WINDOWS_VERSION%*'
    }

    It 'writes a README that names the remaining publishing work' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $readme = Get-GeneratedText -Name tool -File README.md

        $readme | Should -BeLike '*# windows-nano-tool*'
        $readme | Should -BeLike '*<https://example.com/tool.zip>*'
        $readme.EndsWith("`n") | Should -BeTrue
        $readme | Should -BeLike '*smoke-test.ps1*'
        $readme | Should -BeLike '*build-windows-image.yml*'
        $readme | Should -BeLike '*root README image list*'
    }
}

Describe 'New-NanoServerImage version handling' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'promotes the version substring into a build argument' {
        $result = Invoke-Generator -Parameters @{
            Name = 'my-tool'
            Url = 'https://example.com/v1.2.3/tool-1.2.3.zip'
            VersionString = '1.2.3'
            RepositoryRoot = $script:root
        }

        $result.VersionVariable | Should -Be 'MY_TOOL_VERSION'
        $dockerfile = Get-GeneratedText -Name my-tool -File Dockerfile
        $dockerfile | Should -BeLike '*ARG MY_TOOL_VERSION=1.2.3*'
        $dockerfile | Should -BeLike '*ENV MY_TOOL_VERSION=${MY_TOOL_VERSION}*'
        $dockerfile | Should -BeLike '*https://example.com/v%MY_TOOL_VERSION%/tool-%MY_TOOL_VERSION%.zip*'
        $dockerfile | Should -BeLike '*curl -fLo "C:\tool-1.2.3.zip"*'

        $build = Get-GeneratedText -Name my-tool -File build.cmd
        $build | Should -BeLike '*if not defined MY_TOOL_VERSION set "MY_TOOL_VERSION=1.2.3"*'
        $build | Should -BeLike '*--build-arg MY_TOOL_VERSION=%MY_TOOL_VERSION%*'
        $build | Should -BeLike '*-t windows-nano-my-tool:%MY_TOOL_VERSION%-%WINDOWS_VERSION%*'

        $readme = Get-GeneratedText -Name my-tool -File README.md
        $readme | Should -Match ([regex]::Escape('Set `MY_TOOL_VERSION` to override the version'))
    }

    It 'leaves a note when there is no version argument' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile
        $readme = Get-GeneratedText -Name tool -File README.md

        $dockerfile | Should -Not -BeLike '*TOOL_VERSION*'
        $readme | Should -BeLike '*no version build argument*'
    }
}

Describe 'New-NanoServerImage extraction tools' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'uses 7-Zip arguments for 7z.exe' {
        $null = Invoke-Generator -Parameters @{
            Name = 'tool'
            Url = 'https://example.com/tool.zip'
            ExtractionTool = '7z.exe'
            RepositoryRoot = $script:root
        }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile
        $readme = Get-GeneratedText -Name tool -File README.md

        $dockerfile | Should -BeLike '*7z.exe x C:\tool.zip -o"%TOOL_DIR%" -y*'
        $dockerfile | Should -BeLike '*7z.exe is not part of Nano Server*'
        $dockerfile | Should -Not -BeLike '*# # 7z*'
        $readme | Should -BeLike '*7-Zip is not part of Nano Server*'
    }

    It 'uses custom extraction arguments' {
        $null = Invoke-Generator -Parameters @{
            Name = 'tool'
            Url = 'https://example.com/tool.zip'
            ExtractionTool = 'custom.exe'
            ExtractionArguments = 'x {archive} -out "{destination}"'
            RepositoryRoot = $script:root
        }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile

        $dockerfile | Should -BeLike '*custom.exe x C:\tool.zip -out "%TOOL_DIR%"*'
    }
}

Describe 'New-NanoServerImage output safety' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'refuses to overwrite an existing image folder' {
        $parameters = @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $null = Invoke-Generator -Parameters $parameters

        { Invoke-Generator -Parameters $parameters } | Should -Throw -ExpectedMessage '*already exists*'
    }

    It 'overwrites with -Force' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/first.zip'; RepositoryRoot = $script:root }
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/second.zip'; RepositoryRoot = $script:root } -Force

        Get-GeneratedText -Name tool -File README.md | Should -BeLike '*second.zip*'
    }

    It 'creates nothing with -WhatIf' {
        $result = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root } -WhatIf

        Test-Path -LiteralPath $result.Folder | Should -BeFalse
    }
}

Describe 'New-NanoServerImage line endings' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
    }

    It 'writes LF for Dockerfile and README and CRLF for build.cmd' {
        $folder = Join-Path $script:root 'nano-server/nano-server-tool'
        $dockerfile = [System.IO.File]::ReadAllText((Join-Path $folder 'Dockerfile'))
        $readme = [System.IO.File]::ReadAllText((Join-Path $folder 'README.md'))
        $build = [System.IO.File]::ReadAllText((Join-Path $folder 'build.cmd'))

        $dockerfile.Contains("`r`n") | Should -BeFalse
        $readme.Contains("`r`n") | Should -BeFalse
        $build.Contains("`r`n") | Should -BeTrue
    }
}

Describe 'New-NanoServerImage existing image patterns' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
    }

    It 'handles a <Label> artifact URL' -TestCases @(
        @{ Label = 'Go'; Name = 'go'; Url = 'https://go.dev/dl/go1.27.3.windows-amd64.zip'; Version = '1.27.3'; Variable = 'GO_VERSION' }
        @{ Label = 'PHP'; Name = 'php'; Url = 'https://windows.php.net/downloads/releases/archives/php-8.5.12-1-nts-Win32-vs17-x64.zip'; Version = '8.5.12-1'; Variable = 'PHP_VERSION' }
    ) {
        $result = Invoke-Generator -Parameters @{
            Name = $Name
            Url = $Url
            VersionString = $Version
            RepositoryRoot = $script:root
        }

        $result.Image | Should -Be "windows-nano-$Name"
        $result.VersionVariable | Should -Be $Variable
        $dockerfile = Get-GeneratedText -Name $Name -File Dockerfile
        $dockerfile | Should -BeLike "*ARG $Variable=$Version*"
        $dockerfile | Should -BeLike "*$($Url.Replace($Version, "%$Variable%"))*"
    }
}
