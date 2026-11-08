# Nanoserver with Wine, ReactOS and Server Core tools combined

This image adds the console tools nanoserver lacks, picking the implementation that works best for each tool: Wine's unmodified PE programs, ReactOS programs patched with the `__chkstk` shim, or a program copied from Server Core. [`tool-sources.txt`](tool-sources.txt) is the whole configuration: one `<tool>=<source>` line per tool.

It complements the single-source images [`nano-server-wine-tools`](../nano-server-wine-tools/README.md) and [`nano-server-reactos-tools`](../nano-server-reactos-tools/README.md), which this change also adds.

## Build

```cmd
build.cmd
set WINDOWS_VERSION=2022 && build.cmd
```

`WINDOWS_VERSION` is `2019`, `2022` or `2025` (the default).

## Switching a tool's source

Change one line in `tool-sources.txt` and rebuild:

```text
find.exe=wine
```

becomes:

```text
find.exe=reactos
```

Sources are `wine`, `reactos` and `servercore`. The fetch stages extract the candidate lists in `wine-tools.txt` and `reactos-tools.txt`, `scripts/Select-Tools.ps1` copies only the chosen implementation of each tool, and the build fails on a duplicate, an unknown source, or a tool the chosen source did not fetch. The check stage then verifies that every import of every selected tool resolves against the exact nanoserver base.

Defaults follow the prototype evidence. Overlaps (`find`, `fc`, `where`, `whoami`, `tasklist`, `taskkill`, `fsutil`) use Wine, because those programs load unmodified with no shim or patching. Tools only ReactOS provides here (`more`, `tree`, `comp`, `chcp`, `mode`, `help`, `replace`, `doskey`, `cacls`, `nslookup`, `whois`, `ftp`) use ReactOS. Wine-only `start` and `cabarc` use Wine.

## certutil and adding certificates

No `certutil` in this image works, and the tests say so rather than shipping a stub:

- Wine `certutil.exe` is a stub that prints `fixme` and does nothing.
- ReactOS `certutil.exe` loads with the shim, but `-hashfile` failed with error 234 in the prototype.
- Server Core `certutil.exe` imports `NTDSAPI.dll` and `WLDAP32.dll`, which nanoserver does not have (checked locally against the ltsc2025 nanoserver layer), so a copy would fail to load with `0xC0000135`.

What does work is Server Core's `certoc.exe`: its imports are only DLLs nanoserver has, and `certoc -addstore root <file.cer>` is the documented way to add a certificate on nanoserver. The smoke test proves it: as `ContainerAdministrator` it adds the fixture certificate and checks its thumbprint under `HKLM\SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates`. Writing a certificate to that registry store directly is the other proven method, used by the artifact cache.

## Licensing and source

Wine programs are LGPL-2.1-or-later, ReactOS programs GPL-2.0-or-later (some LGPL-2.1 files), and `certoc.exe` comes from Server Core under Microsoft's container image licence. The image carries `COPYING`, `COPYING.LIB`, `WINE-COPYING.LIB` and [`SOURCE.md`](SOURCE.md). Before this image is published, a maintainer must mirror the pinned ReactOS source as a release asset; `SOURCE.md` records that blocker.

## Use

The tools are in `C:\Program Files\combined-tools`, appended to the user `PATH` after the system `PATH`, so nothing nanoserver ships is shadowed. `WINEDEBUG=-all` is set, as in the Wine image.

```cmd
docker run --rm windows-nano-combined-tools:2025 "whoami & where cmd & tree /f C:\tests\fixtures"
```

## Tests

`C:\tests\run-tests.cmd` is baked into the image, prints [TAP](https://testanything.org/), and covers a Wine tool, a ReactOS tool and `certoc` doing real work, plus a load check for every tool in `tool-sources.txt`. `smoke-test.ps1` runs it and then does the `certoc -addstore` check as administrator.

## License

GPL-2.0-or-later and LGPL-2.1-or-later, as above. Licence texts are copied next to the tools in the image.
