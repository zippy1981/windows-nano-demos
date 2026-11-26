# Windows nanoserver WiX MSI builder

A Windows nanoserver container for building Windows MSI installers with
[WiX Toolset v5](https://wixtoolset.org/), [Go](https://go.dev/), and
[MinGit](https://github.com/git-for-windows/git/releases). It is designed
for building `.wixproj`-based MSI installers such as the
[Podman Windows installer](https://github.com/containers/podman/tree/main/contrib/win-installer).

The image contains:

- [.NET SDK](https://dotnet.microsoft.com/) 10.0.404 — required by WiX v5 (`dotnet build`)
- [WiX Toolset](https://wixtoolset.org/) 5.0.2 as a dotnet global tool (`wix` command)
- [Go](https://go.dev/) 1.27.3 — for compiling Go-based projects before packaging
- [MinGit](https://github.com/git-for-windows/git/releases) 2.56.0 — for cloning at build time

`GOPATH` is `C:\users\containeruser\go`. All tools are on the user PATH.
`GOTOOLCHAIN=local` prevents Go from downloading a different toolchain behind your back.

Will be available at <https://hub.docker.com/r/zippy1981/windows-nano-wix>.

## Building

To build the default (Windows 2025) image:

```cmd
build.cmd
```

To build for Windows 2022:

```cmd
set WINDOWS_VERSION=2022
build.cmd
```

To pin a specific .NET SDK version:

```cmd
set DOTNET_SDK_VERSION=10.0.404
build.cmd
```

## Usage

Build a `.wixproj` MSI inside a container:

```cmd
docker run --rm -v %CD%:C:\workspace windows-nano-wix:2025 "cd C:\workspace && dotnet build my-installer.wixproj"
```

Run a quick check that all tools are on PATH:

```cmd
docker run --rm windows-nano-wix:2025 "dotnet --version && wix --version && go version && git --version"
```

## Smoke tests

The quick smoke test (`smoke-test.ps1`) verifies tool presence and builds a minimal WiX MSI:

```powershell
./nano-server/nano-server-wix/smoke-test.ps1 -Image windows-nano-wix:2025
```

The long smoke test (`smoke-test-podman.ps1`) clones Podman, compiles `podman.exe` from Go
source, and builds the full Podman Windows MSI with WiX (30–60 minutes):

```powershell
./nano-server/nano-server-wix/smoke-test-podman.ps1 -Image windows-nano-wix:2025
```
