# Source for the ReactOS programs in this image

The programs in `C:\Program Files\reactos-tools` are from ReactOS and are mostly
GPL-2.0-or-later, with some LGPL-2.1-or-later files that came from Wine. See `COPYING`
and `COPYING.LIB` in the same folder. This is an engineering reading, not legal advice.

## Binaries

They are the x64 PE files from a pinned ReactOS nightly boot CD, patched in one place:
each tool's `kernel32.dll` import descriptor is rewritten to `rosk32sh.dll` (the shim
built from `shim\chkstk.S` and a generated forwarder definition). The patching scripts
are in this repository under `nano-server/nano-server-reactos-tools/scripts/`.

- Build: `reactos-bootcd-0.4.17-dev-1302-ge25c373-x64-msvc-win-dbg.7z`
- URL: <https://iso.reactos.org/bootcd/reactos-bootcd-0.4.17-dev-1302-ge25c373-x64-msvc-win-dbg.7z>
- Size: 87,401,761 bytes
- SHA-256: `afa7b62a626c440874ff04d51eba5c5b2ab357e79a7bd467be47d6f8f4d0d59a`
- Source commit: `e25c37366b65d94985522a931f76351d6b244234` in <https://github.com/reactos/reactos>

## Corresponding source

- Archive: <https://github.com/reactos/reactos/archive/e25c37366b65d94985522a931f76351d6b244234.zip>

Nightlies are purged from `iso.reactos.org`, and pushing this image to Docker Hub
distributes GPL binaries. Before this image is published, a maintainer must mirror the
pinned boot CD `.7z` and the source archive above as GitHub release assets in this
repository (release `reactos-bootcd-0.4.17-dev-1302`) and record the asset URLs here.
Until then this image is build-and-test only; do not publish it.
