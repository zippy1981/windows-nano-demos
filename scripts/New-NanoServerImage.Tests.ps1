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
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:generator = Join-Path $PSScriptRoot 'New-NanoServerImage.ps1'

    function Invoke-Generator {
        param(
            [hashtable]$Parameters,
            [switch]$Force,
            [switch]$Preview
        )
        $arguments = $Parameters.Clone()
        if ($Force) { $arguments['Force'] = $true }
        if ($Preview) { $arguments['WhatIf'] = $true }
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
        $result.Workflow | Should -Be (Join-Path $script:root '.github/workflows/tool-container.yml')
        Test-Path -LiteralPath $result.Dockerfile | Should -BeTrue
        Test-Path -LiteralPath $result.BuildScript | Should -BeTrue
        Test-Path -LiteralPath $result.Readme | Should -BeTrue
        Test-Path -LiteralPath $result.Workflow | Should -BeTrue
    }

    It 'uses a placeholder URL when -Url is omitted' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile
        $dockerfile | Should -BeLike '*https://example.com/download/artifact.zip*'
    }

    It 'accepts cmd environment-variable placeholders in the URL' {
        $url = 'https://github.com/git-for-windows/git/releases/download/v%MINGIT_RELEASE%/MinGit-%MINGIT_BUILD%-64-bit.zip'
        $null = Invoke-Generator -Parameters @{ Name = 'git'; Url = $url; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name git -File Dockerfile

        $dockerfile | Should -BeLike "*$url*"
        $dockerfile | Should -BeLike '*curl -fLo "C:\MinGit-%MINGIT_BUILD%-64-bit.zip"*'
    }

    It 'writes a Dockerfile with the standard base arguments' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $dockerfile = Get-GeneratedText -Name tool -File Dockerfile

        $dockerfile | Should -Match '^# windows-nano-tool: \S.{20,}'
        $dockerfile | Should -BeLike '*ARG WINDOWS_VERSION=2025*'
        $dockerfile | Should -BeLike '*# Docker Hub categories: developer-tools*'
        $dockerfile | Should -BeLike '*ARG BASE_IMAGE=zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}*'
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

    It 'writes a workflow that calls the shared build workflow' {
        $result = Invoke-Generator -Parameters @{ Name = 'my-tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $workflow = [System.IO.File]::ReadAllText($result.Workflow)

        $workflow | Should -BeLike '*name: My Tool container*'
        $workflow | Should -BeLike '*nano-server/nano-server-my-tool/**'
        $workflow | Should -BeLike '*.github/workflows/my-tool-container.yml*'
        $workflow | Should -BeLike '*.github/workflows/build-windows-image.yml*'
        $workflow | Should -BeLike '*uses: ./.github/workflows/build-windows-image.yml*'
        $workflow | Should -BeLike '*context: nano-server/nano-server-my-tool*'
        $workflow | Should -BeLike '*image: windows-nano-my-tool*'
        $workflow | Should -BeLike '*github.event_name == ''pull_request''*'
        $workflow.EndsWith("`n") | Should -BeTrue
    }

    It 'writes a README that names the remaining publishing work' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        $readme = Get-GeneratedText -Name tool -File README.md

        $readme | Should -BeLike '*# windows-nano-tool*'
        $readme | Should -BeLike '*<https://example.com/tool.zip>*'
        $readme.EndsWith("`n") | Should -BeTrue
        $readme | Should -BeLike '*smoke-test.ps1*'
        $readme | Should -BeLike '*.github/workflows/tool-container.yml*'
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

    It 'refuses to overwrite an existing workflow' {
        $workflow = Join-Path $script:root '.github/workflows/tool-container.yml'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $workflow) -Force
        [System.IO.File]::WriteAllText($workflow, 'stale')

        { Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root } } |
            Should -Throw -ExpectedMessage '*already exists*'
    }

    It 'overwrites with -Force' {
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/first.zip'; RepositoryRoot = $script:root }
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/second.zip'; RepositoryRoot = $script:root } -Force

        Get-GeneratedText -Name tool -File README.md | Should -BeLike '*second.zip*'
    }

    It 'overwrites an existing workflow with -Force' {
        $result = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
        [System.IO.File]::WriteAllText($result.Workflow, 'stale')

        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root } -Force

        [System.IO.File]::ReadAllText($result.Workflow) | Should -BeLike '*image: windows-nano-tool*'
    }

    It 'creates nothing with -WhatIf' {
        $result = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root } -Preview

        Test-Path -LiteralPath $result.Folder | Should -BeFalse
        Test-Path -LiteralPath $result.Workflow | Should -BeFalse
    }
}

Describe 'New-NanoServerImage line endings' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:root
        $null = Invoke-Generator -Parameters @{ Name = 'tool'; Url = 'https://example.com/tool.zip'; RepositoryRoot = $script:root }
    }

    It 'writes LF for Dockerfile, README and workflow, and CRLF for build.cmd' {
        $folder = Join-Path $script:root 'nano-server/nano-server-tool'
        $dockerfile = [System.IO.File]::ReadAllText((Join-Path $folder 'Dockerfile'))
        $readme = [System.IO.File]::ReadAllText((Join-Path $folder 'README.md'))
        $workflow = [System.IO.File]::ReadAllText((Join-Path $script:root '.github/workflows/tool-container.yml'))
        $build = [System.IO.File]::ReadAllText((Join-Path $folder 'build.cmd'))

        $dockerfile.Contains("`r`n") | Should -BeFalse
        $readme.Contains("`r`n") | Should -BeFalse
        $workflow.Contains("`r`n") | Should -BeFalse
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
        Test-Path -LiteralPath $result.Workflow | Should -BeTrue
        $dockerfile = Get-GeneratedText -Name $Name -File Dockerfile
        $dockerfile | Should -BeLike "*ARG $Variable=$Version*"
        $dockerfile | Should -BeLike "*$($Url.Replace($Version, "%$Variable%"))*"
    }

    It 'scaffolds the <Label> download used by the <Image> image' -TestCases @(
        @{
            Label = 'Go toolchain'
            Image = 'go'
            Name = 'go-toolchain'
            Url = 'https://go.dev/dl/go%GO_VERSION%.windows-amd64.zip'
            Archive = 'go%GO_VERSION%.windows-amd64.zip'
        }
        @{
            Label = 'MinGit for Go'
            Image = 'go'
            Name = 'mingit-go'
            Url = 'https://github.com/git-for-windows/git/releases/download/v%MINGIT_RELEASE%/MinGit-%MINGIT_BUILD%-64-bit.zip'
            Archive = 'MinGit-%MINGIT_BUILD%-64-bit.zip'
        }
        @{
            Label = 'micro editor for Go'
            Image = 'go'
            Name = 'micro-go'
            Url = 'https://github.com/micro-editor/micro/releases/download/v%MICROEDITOR_VERSION%/micro-%MICROEDITOR_VERSION%-win64.zip'
            Archive = 'micro-%MICROEDITOR_VERSION%-win64.zip'
        }
        @{
            Label = 'llvm-mingw for Go'
            Image = 'go'
            Name = 'llvm-mingw'
            Url = 'https://github.com/mstorsjo/llvm-mingw/releases/download/%LLVM_MINGW_VERSION%/llvm-mingw-%LLVM_MINGW_VERSION%-ucrt-x86_64.zip'
            Archive = 'llvm-mingw-%LLVM_MINGW_VERSION%-ucrt-x86_64.zip'
        }
        @{
            Label = 'Node.js for PHP'
            Image = 'php'
            Name = 'node-php'
            Url = 'https://nodejs.org/dist/v%NODE_VERSION%/node-v%NODE_VERSION%-win-x64.zip'
            Archive = 'node-v%NODE_VERSION%-win-x64.zip'
        }
        @{
            Label = 'PHP'
            Image = 'php'
            Name = 'php'
            Url = 'https://windows.php.net/downloads/releases/archives/php-%PHP_VERSION%-nts-Win32-vs%PHP_VS_VERSION%-x64.zip'
            Archive = 'php-%PHP_VERSION%-nts-Win32-vs%PHP_VS_VERSION%-x64.zip'
        }
        @{
            Label = 'MinGit for Rust'
            Image = 'rust'
            Name = 'mingit-rust'
            Url = 'https://github.com/git-for-windows/git/releases/download/%MINGIT_TAG%/MinGit-%MINGIT_VERSION%-64-bit.zip'
            Archive = 'MinGit-%MINGIT_VERSION%-64-bit.zip'
        }
        @{
            Label = 'Win32-OpenSSH'
            Image = 'ssh'
            Name = 'openssh'
            Url = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/%OPENSSH_VERSION%/OpenSSH-Win64.zip'
            Archive = 'OpenSSH-Win64.zip'
        }
        @{
            Label = 'MySQL'
            Image = 'mysql'
            Name = 'mysql'
            Url = 'https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-%MYSQL_VERSION%-winx64.zip'
            Archive = 'mysql-%MYSQL_VERSION%-winx64.zip'
        }
        @{
            Label = 'Docker CLI'
            Image = 'gh-runner'
            Name = 'docker-cli'
            Url = 'https://download.docker.com/win/static/stable/x86_64/docker-%DOCKER_VERSION%.zip'
            Archive = 'docker-%DOCKER_VERSION%.zip'
        }
        @{
            Label = 'GitHub Actions runner'
            Image = 'gh-runner'
            Name = 'actions-runner'
            Url = 'https://github.com/actions/runner/releases/download/v%RUNNER_VERSION%/actions-runner-win-x64-%RUNNER_VERSION%.zip'
            Archive = 'actions-runner-win-x64-%RUNNER_VERSION%.zip'
        }
        @{
            Label = 'busybox MinGit for the runner'
            Image = 'gh-runner'
            Name = 'mingit-busybox'
            Url = 'https://github.com/git-for-windows/git/releases/download/%MINGIT_TAG%/MinGit-%MINGIT_VERSION%-busybox-64-bit.zip'
            Archive = 'MinGit-%MINGIT_VERSION%-busybox-64-bit.zip'
        }
        @{
            Label = 'FAR'
            Image = 'server-core-far'
            Dockerfile = 'server-core/server-core-far/Dockerfile'
            Name = 'far'
            Url = 'https://www.farmanager.com/files/Far30b%FAR_BUILD%.x64.%FAR_DATE%.7z'
            Archive = 'Far30b%FAR_BUILD%.x64.%FAR_DATE%.7z'
        }
    ) {
        $relativeDockerfile = if ($Dockerfile) { $Dockerfile } else { "nano-server/nano-server-$Image/Dockerfile" }
        $dockerfilePath = Join-Path $script:repoRoot $relativeDockerfile
        [System.IO.File]::ReadAllText($dockerfilePath) | Should -BeLike "*$Url*"

        $parameters = @{ Name = $Name; Url = $Url; RepositoryRoot = $script:root }
        if ($ExtractionTool) { $parameters.ExtractionTool = $ExtractionTool }
        $null = Invoke-Generator -Parameters $parameters

        $download = 'curl -fLo "C:\' + $Archive + '" "' + $Url + '"'
        Get-GeneratedText -Name $Name -File Dockerfile | Should -BeLike "*$download*"
        Get-GeneratedText -Name $Name -File README.md | Should -BeLike "*$Url*"
    }
}
