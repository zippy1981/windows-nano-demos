---
name: version-check
description: List every tool version pinned in this repo's Dockerfiles next to the newest upstream release (GitHub releases, the Go proxy, Node, npm, PHP for Windows, the PowerShell Gallery, rustup, Docker), in one small table, instead of fetching release indexes into context. Use when asked whether anything is outdated, before bumping a pin, and in windows-deps-updater.
---

# Version check

Don't WebFetch `nodejs.org/dist/index.json`, PHP's `releases.json` or GitHub release pages to find versions. The script fetches each upstream once and prints only the answer:

```bash
uv run python scripts/check_versions.py --outdated     # only pins that aren't current
uv run python scripts/check_versions.py --only NODE_VERSION,PHP_VERSION
uv run python scripts/check_versions.py --json         # for scripting
```

Set `GH_TOKEN` (for example `GH_TOKEN=$(gh auth token)`) so the GitHub lookups aren't rate limited.

Each row is `Dockerfile | pin | current | latest | status | note`:

- **current / outdated:** the pin is compared on as many numeric parts as both have, so a `MINGIT_VERSION=2.56.0` pin matches the `2.56.0.4` release.
- **Series pins:** `PHP_VERSION` and `MYSQL_VERSION` report the newest release in the pinned series. PHP's note names the Visual Studio toolset for `PHP_VS_VERSION`, and says when a newer series exists.
- **Notes:** they name the derived values to update with the pin, such as `MICROEDITOR_PATH`, `MINGIT_TAG`, or `FAR_BUILD` and `FAR_DATE`.
- **error:** the lookup failed. The script exits 1, and the note has the reason.
- **no source:** a pin the script doesn't know. Add it to `SOURCES` in `scripts/check_versions.py`. `tests/test_check_versions.py` fails until you do.

After bumping a pin, check the new download URL resolves (`curl -sIL <url>`, which must end at 200), then build and smoke-test it with the `local-image-check` skill. Tool bumps and base-image refreshes are separate changes (ADR 0007).
