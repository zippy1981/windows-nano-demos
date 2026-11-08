# Source for the programs in this image

`tool-sources.txt` says which implementation each tool in `C:\tools\combined` is.

- **wine**: unmodified x86_64 PE programs from WineHQ's `wine-stable-amd64` 11.0.0.0~noble-1
  package (SHA-256 `6cb835e2171b5572b17f1c06729735c2c7e40178239d7fa6c29ef14bd9b40d16`),
  LGPL-2.1-or-later. Source: `wine-11.0.tar.xz` from
  <https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz>. See `WINE-COPYING.LIB`.
  The Wine image in this repository (`nano-server-wine-tools`) carries that tarball in full.
- **reactos**: x64 PE programs from the ReactOS 4.17 nightly
  `reactos-bootcd-0.4.17-dev-1340-gfaa2d03-x64-msvc-win-dbg.7z`
  (SHA-256 `37f8642188a949a109000c96522407ce7b515658b804569f717ac95e7051193b`, source commit
  `faa2d0325a880c8ef56bad1e52e7288176ef9975` in <https://github.com/reactos/reactos>),
  GPL-2.0-or-later with some LGPL-2.1-or-later files. See `COPYING` and `COPYING.LIB`.
  Each tool's `kernel32.dll` import is rewritten to the shim `rosk32sh.dll`, built from
  `shared-tools\shim\chkstk.S`; the patching scripts are in `nano-server\shared-tools\scripts\`.
  Source archive: <https://github.com/reactos/reactos/archive/faa2d0325a880c8ef56bad1e52e7288176ef9975.tar.gz>
  (SHA-256 `b03a9e90a1b1d4ee12ea8076a9533bd742f350234fceed9d87bbe0e23389a90a`)
- **servercore**: `certoc.exe` copied from the Server Core stage of the same Windows
  version as the base image, under Microsoft's container image licence.

Nightlies are purged from `iso.reactos.org`, and pushing this image distributes GPL
binaries. The pinned ReactOS boot CD and source archive are mirrored as assets of release
`reactos-0.4.17-dev-1340-gfaa2d03`, which the `release` job in
`.github/workflows/reactos-tools-container.yml` creates on `main`. The asset URLs are listed in
`nano-server/nano-server-reactos-tools/SOURCE.md`. Until that release exists this image is
build-and-test only; do not publish it. This is an engineering reading, not legal advice.
