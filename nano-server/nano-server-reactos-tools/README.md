# Nanoserver with ReactOS command-line tools

This image adds console tools that nanoserver lacks: `find`, `more`, `fc`, `where`, `whoami`, `tree`, `comp`, `tasklist`, `taskkill`, `chcp`, `mode`, `help`, `replace`, `doskey`, `cacls`, `fsutil`, `nslookup`, `whois` and `ftp`. They are the x64 PE programs from a pinned ReactOS nightly boot CD, patched to run on real Windows.

See [`plans/reactos-binaries.md`](../../plans/reactos-binaries.md) for the design, and [`SOURCE.md`](SOURCE.md) for where the binaries and their source come from.

## Build

```cmd
build.cmd
set WINDOWS_VERSION=2022 && build.cmd
```

`WINDOWS_VERSION` is `2019`, `2022` or `2025` (the default). The ReactOS programs are not in git. The Dockerfile's fetch stage runs `shared-tools/scripts/Fetch-Reactos.ps1` on Server Core, which downloads the pinned boot CD, checks its SHA-256, extracts only the files in `tools.txt`, builds the shim, and patches the tools.

## The shim

ReactOS x64 MSVC binaries import `__chkstk` from `kernel32.dll`. Microsoft's x64 `kernel32.dll` does not export it, so the tools fail to load with `0xC0000139`. The image builds `rosk32sh.dll`: every `kernel32` name the tools import becomes a forwarder to the real `kernel32`, and `__chkstk` is implemented in `shared-tools/shim/chkstk.S`. Each tool's `kernel32.dll` import is rewritten in place to `rosk32sh.dll` by `shared-tools/scripts/Set-PeImportName.ps1`. No ReactOS core DLL is copied into the image.

The builder uses llvm-mingw, not the prototype's Rust toolchain. The generated export table is the same either way: the local verification for this change cross-built the shim on Linux and checked that `__chkstk` is a local export and the other names are forwarders. Only the Windows CI runners can prove the patched tools actually run.

## Licensing and source

ReactOS is mostly GPL-2.0-or-later, with some LGPL-2.1-or-later files from Wine. The image carries `COPYING`, `COPYING.LIB` and `SOURCE.md`. Nightlies expire, so before this image is published a maintainer must mirror the pinned boot CD and its source archive as release assets; [`SOURCE.md`](SOURCE.md) says exactly that. Until then this image is build-and-test only.

## Use

The tools are in `C:\tools\reactos`, appended to the user `PATH` after the system `PATH`, so nothing nanoserver ships is shadowed.

```cmd
docker run --rm windows-nano-reactos-tools:2025 "whoami & where cmd & tasklist"
```

## certutil

ReactOS `certutil.exe` is not shipped. It loads with the shim, but `-hashfile` failed with error 234 in the prototype. Wine's `certutil.exe` is a stub. Server Core's `certutil.exe` cannot be copied either: it imports `NTDSAPI.dll` and `WLDAP32.dll`, which nanoserver does not have, so it would fail with `0xC0000135`. The combined image (`nano-server-combined-tools`) instead ships Server Core's `certoc.exe`, whose imports do resolve, and the tests cover adding a certificate that way. The other proven way to add a certificate on nanoserver is writing it to the registry store under `HKLM\SOFTWARE\Microsoft\SystemCertificates`, as the artifact cache does.

## Tests

`C:\tests\run-tests.cmd` is baked into the image. It prints [TAP](https://testanything.org/) and exits with the number of failures.

```cmd
docker run --rm windows-nano-reactos-tools:2025 C:\tests\run-tests.cmd
```

The suite covers each shipped tool doing real work, a large-file `find /c` that exercises the shim's stack probe, and a load check for every tool in `tools.txt` (no `0xC0000135`, `0xC0000139` or `0xC0000005`).

## Limits

ReactOS nightlies are debug builds of alpha software. Only the tested switches are supported. Tools nanoserver already has are not shipped, and neither are stubs or tools that cannot load (`certutil`, `clip`, `cscript`, `msiexec`, `net`, `reg` and others the plan lists).

## License

ReactOS is licensed under GPL-2.0-or-later; some files are LGPL-2.1-or-later. `COPYING`, `COPYING.LIB` and `SOURCE.md` are copied next to the tools in the image.
