# Node and PHP development windows nano server development container

Node and PHP actually work. A text editor called [micro](https://github.com/micro-editor/micro) is available.

Vite, Composer and the Laravel installer are installed and in your path.

Available at <https://hub.docker.com/repository/docker/zippy1981/windows-nano-php/general>.

## Versions

| Component | Version |
| --- | --- |
| PHP (NTS x64, vs17) | 8.5.12-1 |
| Node.js (LTS) | 26.13.0 |
| npm | 12.2.2 |
| micro | 2.0.15 |
| Composer | latest at build time |

The PHP build enables the `curl`, `fileinfo`, `openssl` and `zip` extensions. The image is built on [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages/tree/main/images/nanoserver-base), which ships the Visual C++ runtime DLLs PHP needs, as well as bsdtar, `jq` and Microsoft Edit (ADR 0017).

## Building

Images are built for Windows Server 2019, 2022 and 2025. `build.cmd` builds 2025 unless `WINDOWS_VERSION` is set:

```cmd
build.cmd
```

To build the Windows 2019 or 2025 container from PowerShell:

```pwsh
$env:WINDOWS_VERSION=2019
./build.cmd
```

From the Command Prompt:

```cmd
set WINDOWS_VERSION=2019
build.cmd
```

The Dockerfile takes two build arguments, and `build.cmd` passes both through when they're set:

- `WINDOWS_VERSION`: `2019`, `2022` or `2025` (default). It picks the base image's tag.
- `BASE_IMAGE`: the base image. It defaults to `zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}`.
