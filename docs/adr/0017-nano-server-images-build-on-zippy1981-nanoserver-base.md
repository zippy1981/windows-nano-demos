# 0017. Nano Server images build on zippy1981/nanoserver-base

- Status: Proposed
- Date: 2026-11-09
- Related: [0004](0004-rebuild-all-images-on-base-image-digest-change.md), [0008](0008-images-take-windows-version-defaulting-to-2025-built-as-a-matrix.md), [0011](0011-repository-conventions-are-enforced-by-tests-in-ci.md), [0012](0012-images-live-in-a-directory-for-their-base-image.md), [#71](https://github.com/zippy1981/windows-nano-demos/issues/71), [#77](https://github.com/zippy1981/windows-nano-demos/issues/77), [plan](../../plans/nanoserver-base-migration.md)

## Context

Every Nano Server image here built on `mcr.microsoft.com/windows/nanoserver` and added the same things itself:

- PHP, MySQL and the editors each had a Server Core stage that installed an unpinned Visual C++ redistributable and copied out `vcruntime140.dll`, `vcruntime140_1.dll` and `msvcp140.dll`.
- The PowerShell and runner images each downloaded PowerShell 7, and the editors image downloaded Microsoft Edit.
- PHP copied `where.exe` from Server Core for one smoke-test line.
- Every image unpacked zips with Windows' own `tar.exe`, which is old on ltsc2019 and ltsc2022 and silently skips files.

[zippy1981/windows-nano-baseimages](https://github.com/zippy1981/windows-nano-baseimages) publishes `zippy1981/nanoserver-base:ltsc2019|ltsc2022|ltsc2025`. Each tag has bsdtar 3.8, `jq` and Microsoft Edit first on `PATH`, Windows' Schannel `curl`, and a pinned, signature-checked Visual C++ runtime in `System32`. The `-pwsh` tags add PowerShell 7. Every tool is pinned by version and SHA-256 there, and tested on all three versions.

## Decision

- **Nano Server images default `BASE_IMAGE` to `zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}`.** An image that runs PowerShell, at build time or as its command, uses the `-pwsh` tag. Server Core images keep `mcr.microsoft.com/windows/servercore:ltsc${WINDOWS_VERSION}-amd64`. `tests/repo_conventions.py` allows only these, and ADR 0012's directory rule follows the base's family.
- **Images don't add what the base provides,** and their smoke tests cover only what each image adds. PowerShell's version isn't pinned here: the PowerShell and runner smoke tests require 7.4 or later.
- **ADR 0004 still holds.** `scripts/refresh_matrix.py` reads the base's digest from Docker Hub, the same way it reads MCR's. The twice-daily image refresh rebuilds an image when its nanoserver-base digest changes, and pins the build to that digest. nanoserver-base itself rebuilds when Microsoft publishes a new Nano Server, so a Patch Tuesday update reaches these images within about two refresh runs.

## Consequences

- Three Server Core stages, two PowerShell downloads, a Microsoft Edit download and the `where.exe` copies are gone. The runtime DLLs are now pinned and verified, where `aka.ms` used to serve whatever was current.
- `tar` in every Nano Server image is bsdtar, which reads zstd and 7z. It shares libarchive's known gaps: Deflate64 zips ([windows-nano-baseimages#7](https://github.com/zippy1981/windows-nano-baseimages/issues/7)) and zips read from a pipe ([#8](https://github.com/zippy1981/windows-nano-baseimages/issues/8)). `tests/test_no_tar_from_pipe.py` forbids the second.
- These images now depend on another repository's releases. A broken nanoserver-base tag breaks their builds until it is fixed there, or `BASE_IMAGE` is pinned to an older digest.
- A base change takes two hops to arrive: Microsoft to nanoserver-base, then nanoserver-base to these images. #77 can still add a cross-repo dispatch, if the polling delay matters.

## Alternatives considered

- **Keep the MCR base and copy what each image needs:** the duplication this removes, with unpinned runtime downloads.
- **Rebuild on a timer instead of the base digest:** #71 proposed this as a stopgap. Reading Docker Hub digests reuses code `refresh_matrix.py` already has for the published labels, so it keeps ADR 0004's rule and doesn't rebuild when nothing changed.
- **A cross-repo dispatch from windows-nano-baseimages:** needs a token with write access to this repository. Deferred to #77.
