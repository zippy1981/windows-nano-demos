# Source for the programs in this image

`tool-sources.txt` says which implementation each tool in `C:\Program Files\combined-tools` is.

- **wine**: unmodified x86_64 PE programs from WineHQ's `wine-stable-amd64` 11.0.0.0~noble-1
  package (SHA-256 `6cb835e2171b5572b17f1c06729735c2c7e40178239d7fa6c29ef14bd9b40d16`),
  LGPL-2.1-or-later. Source: `wine-11.0.tar.xz` from
  <https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz>. See `WINE-COPYING.LIB`.
  The Wine image in this repository (`nano-server-wine-tools`) carries that tarball in full.
- **reactos**: x64 PE programs from the ReactOS nightly
  `reactos-bootcd-0.4.17-dev-1302-ge25c373-x64-msvc-win-dbg.7z`
  (SHA-256 `afa7b62a626c440874ff04d51eba5c5b2ab357e79a7bd467be47d6f8f4d0d59a`, source commit
  `e25c37366b65d94985522a931f76351d6b244234` in <https://github.com/reactos/reactos>),
  GPL-2.0-or-later with some LGPL-2.1-or-later files. See `COPYING` and `COPYING.LIB`.
  Each tool's `kernel32.dll` import is rewritten to the shim `rosk32sh.dll`, built from
  `shim\chkstk.S`; the patching scripts are in this folder's `scripts\`.
  Source archive: <https://github.com/reactos/reactos/archive/e25c37366b65d94985522a931f76351d6b244234.zip>
- **servercore**: `certoc.exe` copied from the Server Core stage of the same Windows
  version as the base image, under Microsoft's container image licence.

Nightlies are purged from `iso.reactos.org`, and pushing this image distributes GPL
binaries. Before this image is published, a maintainer must mirror the pinned ReactOS
boot CD and source archive as GitHub release assets in this repository (release
`reactos-bootcd-0.4.17-dev-1302`) and record the asset URLs here. Until then this image
is build-and-test only; do not publish it. This is an engineering reading, not legal advice.
