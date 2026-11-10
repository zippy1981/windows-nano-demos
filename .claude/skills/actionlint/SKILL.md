---
name: actionlint
description: Lint this repo's GitHub Actions workflows with the pinned actionlint release, downloaded once, checksum-verified and cached outside the repo, with one line per finding. Use after writing or changing any file in .github/workflows/, and instead of looking for actionlint on PATH, downloading it by hand, or running its docker image.
---

# actionlint

```bash
uv run python scripts/actionlint.py                                # every workflow
uv run python scripts/actionlint.py .github/workflows/php-container.yml
```

The first run downloads the pinned release (`VERSION` in `scripts/actionlint.py`) for this OS and checks it against the release's checksums file. It caches the binary in `%LOCALAPPDATA%\actionlint\<version>` on Windows and `~/.cache/actionlint/<version>` elsewhere. Later runs use the cache. `--print-path` prints where the binary is.

- **Output:** one line per finding (`file:line:col: message [rule]`), then `no findings` on success. The exit code is actionlint's, and 2 means the download failed.
- **Config:** `.github/actionlint.yaml` declares the fleet's custom `docker` runner label. A new self-hosted label goes there, not in a per-run flag.
- **Scope:** actionlint checks syntax, expressions and generic mistakes. The repo's own rules (fork guard, runner labels, the shared build workflow) are checked by `uv run pytest`, so run both.

If the download fails, say so in your report rather than claiming the YAML is valid.
