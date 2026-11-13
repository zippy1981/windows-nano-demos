# Neovim on Windows Server Core

[Neovim](https://neovim.io/) and [MinGit](https://github.com/git-for-windows/git/wiki/MinGit), on the path. Git is there so Neovim plugin managers such as lazy.nvim can clone plugins.

Versions are pinned in the `ENV` block of the `Dockerfile`:

- Neovim from the [neovim releases](https://github.com/neovim/neovim/releases) `nvim-win64.zip`
- MinGit (non-busybox, 64-bit) from [Git for Windows](https://github.com/git-for-windows/git/releases), installed to `C:\Program Files\MinGit`

## Why Server Core

Neovim can't start on Nano Server. `nvim.exe` imports `kernel32!DebugBreakProcess`, and the Nano Server ltsc2019, ltsc2022 and ltsc2025 images don't export it. Neovim exits there with `0xC0000139` (`STATUS_ENTRYPOINT_NOT_FOUND`). So the image is based on Server Core for every version, and lives under `server-core/` (ADR 0012).

Neovim needs the Visual C++ runtime (`vcruntime140.dll`). Server Core doesn't ship it, so the `Dockerfile` copies it from [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages), which does. Nothing is copied from the host.

## One Neovim version for every Windows version

An earlier version of this image pinned older Neovim releases for ltsc2019 and ltsc2022, because newer ones failed there: `0xC0000142` on ltsc2019, and a silent exit with 255 on ltsc2022. The releases were not the cause.

- **Neovim 0.11.2, 0.11.6 and 0.12.6 all start and run Lua** on Server Core ltsc2019, ltsc2022 and ltsc2025 under Hyper-V isolation, when the unpacked zip is copied into a container.
- **The failure comes from the zip's own `DbgHelp.dll` in an image layer.** On ltsc2022 under Hyper-V isolation, `nvim.exe` exits with 255 as ContainerAdministrator and `0xC0000142` as ContainerUser while that file is there. Renaming it, or deleting it and writing the same bytes back, makes Neovim start. Under process isolation it starts either way. We don't know why the file fails only after it has been committed to a layer.
- **The `Dockerfile` deletes that `DbgHelp.dll`.** Neovim then loads the `dbghelp.dll` of Windows, which it only uses to write crash reports.

So every Windows version gets the same Neovim. The fix was tested on ltsc2022. CI tests ltsc2019 and ltsc2025.

## Building

To build a 2025 container, the default:

```cmd
build.cmd
```

To build the Windows 2019 container, from PowerShell:

```pwsh
$env:WINDOWS_VERSION=2019
./build.cmd
```

Or from the Command Prompt:

```cmd
set WINDOWS_VERSION=2019
build.cmd
```

## Running

Start an interactive session:

```cmd
docker run -it --rm windows-servercore-neovim:2025 nvim
```

Run Neovim headless. Pass each argument separately: if you pass one string with embedded double quotes, docker escapes them as `\"`, which `cmd.exe` doesn't understand.

```cmd
docker run --rm windows-servercore-neovim:2025 nvim --headless -c "lua io.write('ok')" -c q
```

## Testing

`smoke-test.ps1 -Image <tag>` checks that Neovim starts, runs Lua headless and writes a file, and that `git` runs. The `Neovim container` workflow runs it for 2019, 2022 and 2025.
