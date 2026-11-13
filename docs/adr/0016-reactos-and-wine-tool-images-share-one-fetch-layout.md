# 0016. The ReactOS and Wine tool images share one fetch layout

- Status: Proposed
- Date: 2026-11-08
- Related: [0009](0009-all-image-builds-use-one-reusable-workflow.md), [0011](0011-repository-conventions-are-enforced-by-tests-in-ci.md), [0012](0012-images-live-in-a-directory-for-their-base-image.md), [0013](0013-the-go-image-has-a-cgo-variant-using-llvm-mingw.md), [0014](0014-artifact-cache-with-caddy-on-ltsc2025.md)

## Context

Three images carry command-line tools that Nano Server lacks: `windows-nano-wine-tools` (Wine programs), `windows-nano-reactos-tools` (ReactOS programs) and `windows-nano-combined-tools` (both, plus Server Core's `certoc.exe`). Their Dockerfiles each had their own copy of the import check (`Test-PeImports.ps1`), the shim builder, and the ReactOS and Wine fetch scripts. The copies had drifted, and the ReactOS pin lived in two places. The tools also went to `C:\Program Files\<name>-tools`, and both licence sets went to the same folder in the combined image.

Two constraints shape the layout. A Dockerfile can only `COPY` files inside its build context, and the three images must build from the same context to share files. The images also need a version of ReactOS that is still downloadable: nightlies are purged from `iso.reactos.org`, so the pinned build must be mirrored before the image is published.

## Decision

- **Shared files live in `nano-server/shared-tools/`**: `scripts/` (`Fetch-Reactos.ps1`, `fetch-wine.ps1`, `Test-PeImports.ps1`, `Get-PeImport.ps1`, `New-ShimDef.ps1`, `Set-PeImportName.ps1`) and `shim/chkstk.S`. Each image's fetch and check stages copy what they need from there.
- **The build context is `nano-server/`** for all three tool images. Each Dockerfile is passed with `-f`, and `nano-server/.dockerignore` excludes everything except the shared folder and the three tool folders, so a change elsewhere in `nano-server/` does not invalidate the cache. The shared workflow takes a `build-context` input for this; the other images keep building from their own folder.
- **Installation paths**: Wine programs go to `C:\tools\wine`, ReactOS programs to `C:\tools\reactos`, and the combined image to `C:\tools\combined`. Each folder holds that image's licence texts and `SOURCE.md`. The combined image has its own licence copy, so it does not depend on the other two.
- **The ReactOS version is a Dockerfile argument**, `REACTOS_VERSION`, defaulting to `4.17`. It is passed to `Fetch-Reactos.ps1 -ReactosVersion`, which looks up the pinned boot CD (name, SHA-256 and source commit) in its `$rosBuilds` table, and it sets the `org.reactos.version` label. A version without a pin fails the build instead of downloading something unpinned.
- **The pinned ReactOS build is the x64 MSVC nightly `0.4.17-dev-1340-gfaa2d03`**, the newest 4.17 nightly whose commit resolves on GitHub. The source archive for that commit is published as a release asset of this repository, with the boot CD, so the build can be reproduced after the nightly is purged.

## Consequences

- One place to change the ReactOS pin, and one place to fix the import check or the shim. Each image's Dockerfile still runs its own check stage against its own base, so a missing DLL in one image fails only that image's build.
- Tools move from `C:\Program Files\<name>-tools` to `C:\tools\<name>`. Anything that hard-coded the old path must change. The tests and smoke scripts in this repository are updated; a user's own scripts that refer to the old path will need the same change.
- The combined image's licence and `SOURCE.md` files are copies of the other two images' files. They are duplicated on purpose, because each image must ship its own licence texts.
- Changes to `nano-server/shared-tools/` trigger all three tool image workflows.
- The ReactOS release is created by the pipeline, not by hand. The `source` job in `reactos-tools-container.yml` downloads the source archive and boot CD, checks both SHA-256 pins, and uploads them as a build artifact. The `release` job runs only on `main`, after the image build passes, and publishes that artifact as release `reactos-0.4.17-dev-1340-gfaa2d03`. It skips the step if the release already exists. Until the first run on `main` has created the release, the ReactOS and combined images must stay build-and-test only, and must not be published.
- The `release` job is the one job outside `image-refresh.yml` that writes to the repository. It holds `contents: write` for that job only; the workflow default is `contents: read`. This departs from the rule that only `image-refresh.yml` publishes, because a release is not a Docker Hub image.

## Alternatives considered

- **One Dockerfile that builds all three tool sets.** It would make the combined image trivial, but a change to one tool set would rebuild all three, and each image would have to publish the others' licences.
- **Use a base image that already holds the tools.** That moves the problem into another image and adds a layer that has to be kept in sync with the tool pins.
- **Copy the shared scripts into each image folder.** That is the drift this decision removes.
- **Keep the old `C:\Program Files\<name>-tools` paths.** Rejected because the layout was requested with `C:\tools\wine` and `C:\tools\reactos`.
