# Source for the ReactOS programs in this image

The programs in `C:\tools\reactos` are from ReactOS and are mostly
GPL-2.0-or-later, with some LGPL-2.1-or-later files that came from Wine. See `COPYING`
and `COPYING.LIB` in the same folder. This is an engineering reading, not legal advice.

## Binaries

They are the x64 PE files from a pinned ReactOS nightly boot CD, patched in one place:
each tool's `kernel32.dll` import descriptor is rewritten to `rosk32sh.dll` (the shim
built from `shared-tools\shim\chkstk.S` and a generated forwarder definition). The
fetch and patching scripts are in this repository under `nano-server/shared-tools/scripts/`.

- Version: 4.17 (`REACTOS_VERSION` in the Dockerfile, also the `org.reactos.version` label)
- Build: `reactos-bootcd-0.4.17-dev-1340-gfaa2d03-x64-msvc-win-dbg.7z`
- URL: <https://iso.reactos.org/bootcd/reactos-bootcd-0.4.17-dev-1340-gfaa2d03-x64-msvc-win-dbg.7z>
- SHA-256: `37f8642188a949a109000c96522407ce7b515658b804569f717ac95e7051193b`
- Source commit: `faa2d0325a880c8ef56bad1e52e7288176ef9975` in <https://github.com/reactos/reactos>

## Corresponding source

- Archive: <https://github.com/reactos/reactos/archive/faa2d0325a880c8ef56bad1e52e7288176ef9975.tar.gz>
- SHA-256 of the archive: `b03a9e90a1b1d4ee12ea8076a9533bd742f350234fceed9d87bbe0e23389a90a`

Nightlies are purged from `iso.reactos.org`, and pushing this image to Docker Hub
distributes GPL binaries. The `release` job in `.github/workflows/reactos-tools-container.yml`
mirrors the pinned boot CD and the source archive as assets of release
`reactos-0.4.17-dev-1340-gfaa2d03` once that job's build passes on `main`. The assets are:

- `https://github.com/zippy1981/windows-nano-demos/releases/download/reactos-0.4.17-dev-1340-gfaa2d03/reactos-0.4.17-dev-1340-gfaa2d03-src.tar.gz`
- `https://github.com/zippy1981/windows-nano-demos/releases/download/reactos-0.4.17-dev-1340-gfaa2d03/reactos-bootcd-0.4.17-dev-1340-gfaa2d03-x64-msvc-win-dbg.7z`

Do not publish this image until that release exists. Until then it is build-and-test only.
