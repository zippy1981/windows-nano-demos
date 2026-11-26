<#
.SYNOPSIS
Smoke tests a built windows-nano-wix image: verifies dotnet, wix, go, and git are on PATH, and builds a
minimal WiX MSI from scratch to confirm WiX v5 is fully functional end-to-end.
.EXAMPLE
./nano-server/nano-server-wix/smoke-test.ps1 -Image windows-nano-wix:2025
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image
)
$ErrorActionPreference = 'Stop'

$suffix = [guid]::NewGuid().ToString('n').Substring(0, 8)
$smokeImage = "wix-smoke-minimal:$suffix"

function Build-Derived([string]$Tag, [string]$Dockerfile) {
    $Dockerfile.Replace('__IMAGE__', $Image) | docker build --memory 4g -t $Tag -
    if ($LASTEXITCODE) { throw "building $Tag failed: $LASTEXITCODE" }
}

try {
    # Verify every tool is on PATH and reports a version.
    docker run --rm $Image "dotnet --version && go version && git --version"
    if ($LASTEXITCODE) { throw "tool PATH check failed: $LASTEXITCODE" }

    # Verify WiX is installed as a global dotnet tool.
    $wixList = docker run --rm $Image "dotnet tool list --global"
    if ($LASTEXITCODE) { throw "dotnet tool list failed: $LASTEXITCODE" }
    if ($wixList -notmatch 'wix') { throw "wix not found in dotnet global tools: $wixList" }
    Write-Host "WiX global tool: $($wixList | Select-String 'wix')"

    # Verify GOTOOLCHAIN=local so go never downloads a different toolchain.
    $gotoolchain = docker run --rm $Image "go env GOTOOLCHAIN"
    if ($LASTEXITCODE) { throw "go env GOTOOLCHAIN failed: $LASTEXITCODE" }
    if ($gotoolchain.Trim() -ne 'local') { throw "expected GOTOOLCHAIN=local, got: $gotoolchain" }

    # Build a minimal WiX v5 MSI inside a derived image to verify the full WiX toolchain works.
    # Uses PowerShell to write the .wixproj and .wxs files, then dotnet build to compile them.
    Build-Derived $smokeImage @'
FROM __IMAGE__
WORKDIR C:/users/containeruser/wix-smoke
SHELL ["pwsh","-NoLogo","-NoProfile","-Command","$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';"]
RUN Set-Content smoke.wixproj '<Project Sdk="WixToolset.Sdk/5.0.2"><PropertyGroup><OutputName>smoke</OutputName></PropertyGroup></Project>'
RUN Set-Content smoke.wxs '<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"><Package Name="Smoke" Version="1.0.0" Manufacturer="SmokeTest" UpgradeCode="a1b2c3d4-e5f6-7890-abcd-ef1234567890"><MajorUpgrade DowngradeErrorMessage="A newer version is already installed."/><Feature Id="Main"/></Package></Wix>'
RUN dotnet build smoke.wixproj
'@
    $msiCheck = docker run --rm $smokeImage "dir smoke.msi"
    if ($LASTEXITCODE) { throw "minimal MSI not found after build: $msiCheck" }
    Write-Host "Minimal WiX MSI built: $($msiCheck | Select-String 'smoke.msi')"

    Write-Host "All smoke tests passed for $Image"
}
finally {
    docker rmi -f --no-prune $smokeImage 2>$null | Out-Null
}
