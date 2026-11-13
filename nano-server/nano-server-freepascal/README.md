# Free Pascal on Windows nano server

The [Free Pascal](https://www.freepascal.org/) 3.2.2 compiler for 64-bit Windows, with its runtime library and every package of the release, on Nano Server.

```cmd
docker run --rm zippy1981/windows-nano-freepascal:2025 "fpc -FE. C:\fpc\examples\hello.pas && hello.exe"
```

The stock release can't start on Nano Server, and neither can the programs it builds. This image patches it so both do. [What is patched](#what-is-patched) says how, and what that costs.

## What is in the image

| Path | What it holds |
| --- | --- |
| `C:\fpc\bin\x86_64-win64` | `fpc.exe`, the compiler `ppcx64.exe`, `fpc.cfg`, and the 64-bit tools, such as `fpcres`, `instantfpc`, `fpcmake`, `fpdoc`, `h2pas`, `pas2js` and `ppudump`. It is on the user `PATH`. |
| `C:\fpc\units\x86_64-win64` | The runtime library (`rtl`) and every package: `fcl-base`, `fcl-json`, `fcl-web`, `rtl-generics` and the rest |
| `C:\fpc\examples` | `hello.pas` and `inventory.pas`, which the smoke test compiles |
| `C:\fpc\doc` | The licences and release notes |

`FPCDIR` is `C:\fpc`, and `FREEPASCAL_VERSION` is the installed version.

## What is patched

`Install-FreePascal.ps1` runs in a Server Core build stage. It downloads the release, checks its SHA-256, and changes three things.

- **One import name, in every program and in the `fpintres` unit.** Every program Free Pascal builds imports `EnumResourceTypesA` from `kernel32.dll`, and so does the compiler, which is built with itself. Nano Server's `kernel32.dll` doesn't export it, so nothing starts: the exit code is `-1073741511` (`0xC0000139`, entry point not found). The script replaces the name with `EnumResourceTypesW`, which Nano Server has and which takes the same arguments. It patches the unit as well as the programs, so what you compile in the image starts on Nano Server too.
- **The 32-bit GNU tools are left out.** `as`, `ld`, `make`, `strip`, `windres` and the rest of the release's binutils are 32-bit, and Nano Server can't run 32-bit programs. The compiler doesn't need them on this target: it assembles and links internally.
- **Three tools are left out:** `fppkg` and `fpcmkcfg` need `SHFileOperation` from `shell32.dll`, and `importtl` needs `GetErrorInfo` from `ole32.dll`. Nano Server has neither function. `fpc.cfg`, which `fpcmkcfg` would write, is written by the script.

What that costs:

- **`EnumResourceTypes` gets wide strings.** The function of that name in the resource units is the only caller of the patched import. Its callback expects ANSI names of resource types and now gets UTF-16 ones. Numbered resource types are unaffected.
- **No `make`,** so nothing that builds through makefiles works, including building Free Pascal itself.
- **No `windres`,** so `.rc` files can't be compiled.
- **No package manager.** Every package of the release is already installed.
- **Other missing imports are not patched.** A program whose units import something else Nano Server lacks still won't start there. `importtl` is an example.

Programs compiled in the image are ordinary 64-bit Windows programs. They also run outside Nano Server.

## Building

To build a 2025 container, the default:

```cmd
build.cmd
```

Set `WINDOWS_VERSION` to 2019, 2022 or 2025 first to build another version, and `BASE_IMAGE` to override the base image.

To install another release, pass `--build-arg FREEPASCAL_VERSION=<version>` and `--build-arg FREEPASCAL_SHA256=<hash>` to `docker build`. freepascal.org publishes no checksums, so the hash pins the file the image was tested with. `Install-FreePascal.ps1` stops if a program in the new release no longer has the import it patches.

## Using it

Compile a file from a folder you copy in, and copy the program out:

```pwsh
docker create --name fpc zippy1981/windows-nano-freepascal:2025 "mkdir out && fpc -FEout C:\src\myprogram.pas"
docker cp ./src fpc:C:/src
docker start -a fpc
docker cp fpc:C:/Users/ContainerUser/out ./out
docker rm fpc
```

The output goes to `out` in the container user's home folder, which is the working folder.

The entry point is `cmd /S /C`, so the command is one quoted string. For a shell, run `docker run -it --rm zippy1981/windows-nano-freepascal:2025 cmd`.

## Testing

`smoke-test.ps1 -Image <tag>` compiles and runs both examples, starts each of ten tools, and checks that none of the programs that can't run were left in the image. The `Free Pascal container` workflow runs it for 2019, 2022 and 2025.
