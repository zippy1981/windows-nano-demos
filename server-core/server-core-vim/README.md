# Vim on Windows Server Core

The console version of [Vim](https://www.vim.org/) (`vim.exe`) and [MinGit](https://github.com/git-for-windows/git/wiki/MinGit), on the path. Git is there so Vim plugin managers can clone plugins.

Versions are pinned in the `ENV` block of the `Dockerfile`:

- Vim from the [vim-win32-installer](https://github.com/vim/vim-win32-installer/releases) x64 zip
- MinGit (non-busybox, 64-bit) from [Git for Windows](https://github.com/git-for-windows/git/releases), installed to `C:\Program Files\MinGit`

## Why Server Core

Vim can't start on Nano Server. `vim64.dll` imports `kernel32!DebugBreakProcess`, plus a few `gdi32` and `winmm` functions, and the Nano Server ltsc2019, ltsc2022 and ltsc2025 images don't export them. Vim exits there with `0xC0000139` (`STATUS_ENTRYPOINT_NOT_FOUND`). So the image is based on Server Core for every version, and lives under `server-core/` (ADR 0012).

The bundled `libsodium.dll`, which `:X` encryption uses, needs `vcruntime140.dll`. Server Core doesn't ship it, so the `Dockerfile` copies it from [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages), which does. Nothing is copied from the host.

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
docker run -it --rm windows-servercore-vim:2025 vim
```

Run Vim non-interactively. Pass each argument separately: if you pass one string with embedded double quotes, docker escapes them as `\"`, which `cmd.exe` doesn't understand.

```cmd
docker run --rm windows-servercore-vim:2025 vim -Nu NONE -Es -c "put ='hello'" -c "wq t.txt" "&&" type t.txt
```

## Testing

`smoke-test.ps1 -Image <tag>` checks that Vim starts, writes a file in Ex mode and reports the `win32` feature, and that `git` runs. The `Vim container` workflow runs it for 2019, 2022 and 2025.
