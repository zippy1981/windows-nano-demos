# Console text editors on Windows Nano Server

Terminal text editors that run in a Nano Server container, so the dev images here can offer more than `micro`. This is phase 1 of [plans/console-editors.md](../../plans/console-editors.md):

| Editor | Version | Command | Notes |
| --- | --- | --- | --- |
| [Microsoft Edit](https://github.com/microsoft/edit) | The base image's | `edit` | Comes from [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages/tree/main/images/nanoserver-base), which this image is built on (ADR 0016). Loads `icu.dll` at run time for Unicode-aware search and word wrap. Nano Server has no `icu.dll`, so those fall back to simpler behaviour. |
| [GNU nano](https://github.com/okibcn/nano-for-windows) (okibcn's Windows port) | 7.2 | `nano` | **Not on ltsc2019**: it exits with `0xC0000139` (entry point not found) there, so that image leaves it out. Built with MinGW against the UCRT. The port's last release is from April 2023. A sample `.nanorc` is in `C:\Program Files\nano`; copy it to `%USERPROFILE%\.nanorc` to use it. |
| [Helix](https://helix-editor.com/) | 25.07.1 | `hx` | Needs `vcruntime140.dll` and `vcruntime140_1.dll`, which the base image ships. `HELIX_RUNTIME` points at its themes and grammars. No language servers are installed. |

## Running

The editors need a console, so run the image interactively:

```cmd
docker run -it --rm windows-nano-editors:2025
edit hello.txt
```

There is no clipboard in Nano Server, so copy and paste between the editor and the host don't work.

## Building

```cmd
build.cmd
set WINDOWS_VERSION=2022 && build.cmd
```

Builds use `--memory 4g`, because the default 1 GB Hyper-V limit can hang a build.

The Dockerfile downloads nano and Helix in a Server Core stage with `Get-VerifiedZip.ps1`:

- It checks each zip's pinned SHA-256.
- It unpacks with 7-Zip, because the nano zip uses Deflate64. Windows PowerShell's `Expand-Archive` can't decompress that, and `tar.exe` silently writes it as zero bytes.
- It checks that each executable starts with the `MZ` header.

The final Nano Server stage copies each editor into its own layer under `C:\Program Files\<editor>`.

## Tests

`smoke-test.ps1` runs in CI for ltsc2019, ltsc2022 and ltsc2025 through the shared workflow. CI has no TTY, so it checks:

- `nano --version` and `hx --version` print the pinned versions. Edit comes from the base image, whose own smoke test checks it.
- `hx --health` lists the languages from its runtime folder

It doesn't type into the editors. The interactive test, which types text, saves and quits through a pseudo console, is phase 2 of the plan.
