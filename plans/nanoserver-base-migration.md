# Plan: build the Nano Server images on zippy1981/nanoserver-base

## Goal

Phase 1 of [#71](https://github.com/zippy1981/windows-nano-demos/issues/71): every Nano Server image builds `FROM zippy1981/nanoserver-base:ltsc<ver>` (or `-pwsh`) instead of `mcr.microsoft.com/windows/nanoserver`, drops what the base already provides, and passes CI on ltsc2019, ltsc2022 and ltsc2025.

## Context

- The base ([windows-nano-baseimages](https://github.com/zippy1981/windows-nano-baseimages/tree/main/images/nanoserver-base)) has bsdtar 3.8.11, `jq` and Microsoft Edit first on `PATH` in `C:\tools\bin`, and `curl` is `System32\curl.exe`. Since [windows-nano-baseimages#14](https://github.com/zippy1981/windows-nano-baseimages/issues/14) it also has `vcruntime140.dll`, `vcruntime140_1.dll` and `msvcp140.dll` in `System32`. The `-pwsh` tags add PowerShell 7.6.9 in `C:\Program Files\PowerShell\7`.
- Nine images are in scope: artifact-cache, editors, gh-runner, go, mysql, php, powershell, rust and ssh. editors, mysql and php each have a Server Core `vc_redist` stage. php copies `where.exe`. powershell and gh-runner download PowerShell 7.6.9 themselves. editors ships its own Microsoft Edit.
- `scripts/refresh_matrix.py` only reads base digests from MCR, and raises an error for any other base. `tests/repo_conventions.py` only allows the MCR base in `ARG BASE_IMAGE`.

## Decisions

- **Rebuild trigger:** `refresh_matrix.py` learns to read `zippy1981/nanoserver-base` digests from Docker Hub, the same way it reads MCR's. The twice-daily run then rebuilds an image when its base changed (ADR 0004), instead of on a timer. This answers most of [#77](https://github.com/zippy1981/windows-nano-demos/issues/77).
- **Pull requests:** three, in the order below. PR 1 doesn't need the new base. PR 2 needs the base published with the runtime DLLs.
- **Far:** check whether Far can run on the base before moving it. If it can't, `server-core-far` stays as it is, and the plan records why.

## Phases

### PR 1: never pipe into tar

- [x] `tests/test_no_tar_from_pipe.py` fails on any `| tar` (or `bsdtar`, `tar.exe`, with a path or quotes) outside a comment, in every Dockerfile, cmd, PowerShell and shell script and workflow.
- [x] The rule is in CLAUDE.md, AGENTS.md and DEVELOPER.md.
- [x] This plan.

### PR 2: switch the images

- [ ] **adr:** a new ADR: Nano Server images build on `zippy1981/nanoserver-base`, `-pwsh` where the image runs PowerShell, and the base's tools aren't added again.
- [ ] **python-author:** `BASE_IMAGE_ARG` in `tests/repo_conventions.py` and `scripts/refresh_matrix.py` accept `zippy1981/nanoserver-base:ltsc${WINDOWS_VERSION}` and `-pwsh` under `nano-server/`. `refresh_matrix.py` reads Hub digests for them. Coverage of `scripts/` stays at 95% or more.
- [ ] **container-author:** each Nano Server Dockerfile defaults `BASE_IMAGE` to the base.
  - editors, mysql, php: remove the `vc_redist` stage and the `COPY` of the DLLs.
  - php: run `micro -version` instead of `where micro`, and remove the `where.exe` copies.
  - powershell, gh-runner: `-pwsh`, without their own PowerShell download. gh-runner keeps its `powershell.exe` copy.
  - editors: remove its own Microsoft Edit.
- [ ] **powershell-author:** smoke tests stop checking what the base provides.
- [ ] Docs: CLAUDE.md, AGENTS.md, DEVELOPER.md, the image READMEs, and the `.claude` agents and skills that quote the MCR base.
- [ ] **ci-watcher:** every Nano Server image's CI is green on 2019, 2022 and 2025.

### PR 3: Far and Server Core

- [ ] **windows-container-tester:** check Far's imports against the base on each version, and try `far.exe -?`. Report whether it can run.
- [ ] If it can, move Far to `nano-server/` and stop downloading 7-Zip. If it can't, record why here and in Far's README.
- [ ] Open an issue on windows-nano-baseimages for a Server Core image with bsdtar.

## Not in this plan

- Rows 2–5 of #71 keep their 7-Zip and download-to-file workarounds until [windows-nano-baseimages#7](https://github.com/zippy1981/windows-nano-baseimages/issues/7) and [#8](https://github.com/zippy1981/windows-nano-baseimages/issues/8) are fixed. Their comments link those issues.

## Risks

- **The base's `USER` is `ContainerUser`,** as on MCR's Nano Server. Steps that write to `Program Files` or the machine `PATH` still need `USER ContainerAdministrator`.
- **`tar` is now bsdtar,** not Windows' tar. Each image's extraction is checked by its smoke test, and Deflate64 zips still need 7-Zip.
- **The runner fleet runs `windows-nano-gh-runner`.** A rebuilt runner image only takes effect when the fleet is recreated, so a broken one shows up in its own CI first.
