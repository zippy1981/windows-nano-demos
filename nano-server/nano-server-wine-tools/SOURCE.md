# Source for the Wine programs in this image

The programs in `C:\Program Files\wine-tools` are from Wine and are licensed under the GNU Lesser General Public License, version 2.1 or later. See `COPYING.LIB`, `LICENSE` and `AUTHORS` in the same folder.

## Binaries

They are the unmodified x86_64 PE files from WineHQ's Ubuntu 24.04 (noble) package. They are copied out of `opt/wine-stable/lib/wine/x86_64-windows/`, and nothing is patched or rebuilt.

- Package: `wine-stable-amd64`, version `11.0.0.0~noble-1`
- URL: <https://dl.winehq.org/wine-builds/ubuntu/pool/main/w/wine/wine-stable-amd64_11.0.0.0~noble-1_amd64.deb>
- Size: 122,823,532 bytes
- SHA-256: `6cb835e2171b5572b17f1c06729735c2c7e40178239d7fa6c29ef14bd9b40d16`

## Corresponding source

- Wine version: 11.0
- Tarball: <https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz>
- Size: 33,172,240 bytes
- SHA-256: `c07a6857933c1fc60dff5448d79f39c92481c1e9db5aa628db9d0358446e0701`
- Signature: <https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz.sign>
- Git tag: `wine-11.0` (`ce295733f9a67970b7f60d7af201f2ac16441a50`) in <https://gitlab.winehq.org/wine/wine>

Each program's source is in `programs/<name>/` of that tarball.

**The image carries this tarball.** `C:\Program Files\wine-tools\source\wine-11.0.tar.xz` is the unmodified release tarball, with WineHQ's detached signature `wine-11.0.tar.xz.sign` next to it. The Dockerfile downloads both and checks the tarball's SHA-256 above before it copies them in, so every published image, including those on Docker Hub, comes with its complete corresponding source. To check the signature, use WineHQ's key: `gpg --verify wine-11.0.tar.xz.sign wine-11.0.tar.xz`.

To copy it out of an image:

```cmd
docker create --name wine-src zippy1981/windows-nano-wine-tools:2025
docker cp "wine-src:C:\Program Files\wine-tools\source" .
docker rm wine-src
```

## How the files were extracted

The scripts that pick the files are in <https://github.com/zippy1981/windows-nano-demos> under `nano-server/nano-server-wine-tools/`. `fetch-wine.ps1` runs in the Dockerfile's Server Core ltsc2025 download stage, and `tools.txt` lists the programs. `extract-wine.sh` does the same on Linux for the from-source comparison job. There are no patches.
