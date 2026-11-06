# Docker Hub description, categories and overview

## Goal

Issue #56: every published repository on Docker Hub has:

- a short description that says what the image is;
- the image folder's README as its overview;
- one to three categories that fit the image.

## Context

- `scripts/Publish-DockerHubDocs.ps1` already sets the short description, from the Dockerfile header's first line, and the overview, from `README.md` with links rewritten. The shared workflow runs it with `-WhatIf` on every build and for real after each publish from `main`.
- On 2026-11-06 all 11 `zippy1981/windows-*` repositories had `"categories": []`.
- Docker Hub's categories are a fixed list of 16 (`GET https://hub.docker.com/v2/categories`), and a repository can have up to three. The Hub API's OpenAPI spec documents `categories` on repositories only in responses, plus a `category.updated` audit event. Docker's docs set them only in the web UI.
- Two descriptions needed attention:
  - `windows-nano-artifact-cache` said "(issue #24, ADR 0014)";
  - the old `windows-nano-far` repository, from before ADR 0012 renamed Far to `windows-servercore-far`, has an empty description.

## Decisions

1. **Categories live in the Dockerfile header**, as `# Docker Hub categories: <slug>[, <slug>...]` on the second line, next to the description they go with. `tests/test_dockerfile_docs.py` checks the line:
   - it is present, with one to three slugs and no duplicates;
   - every slug is in a pinned copy of the 16.
2. **The suggested categories** (the issue's first criterion):

   | Image | Categories |
   | --- | --- |
   | artifact-cache | integration-and-delivery, networking, web-servers |
   | gh-runner | integration-and-delivery, developer-tools |
   | go, rust, php, powershell | languages-and-frameworks, developer-tools |
   | editors, servercore-far | developer-tools |
   | mysql | databases-and-storage |
   | ssh | networking, security |

   `operating-systems` is left out on purpose. The images run on Windows, but they aren't OS base images, and that category would bury them among real ones. The dockerfile-docs skill has the rule of thumb for new images.
3. **Setting categories is best effort.** The script sends them with the repository `PATCH`, the same endpoint that sets the description, then reads them back. If they don't match, it prints a GitHub `::warning::` naming the categories and the UI path, and the publish still succeeds. That way an undocumented endpoint can never block publishing images.
4. **Descriptions have no internal references.** A test rejects `#<n>`, `ADR` and `issue` in the first line.
5. **A `Docker Hub docs` workflow** (`dockerhub-docs.yml`) applies documentation to every published repository without rebuilding:
   - it runs by hand only, only on `main`, in the publish environment;
   - it never pushes or deletes, which a test checks.

## Plan

- [x] **container-author**: category lines in all 10 Dockerfiles, and the artifact-cache description reworded. Accept: `uv run pytest -q tests/test_dockerfile_docs.py` passes.
- [x] **powershell-author**: `Publish-DockerHubDocs.ps1` reads, checks and prints the categories (`-WhatIf`), then sets and verifies them. Accept: `-WhatIf` lists the categories for every image, and PSScriptAnalyzer is clean.
- [x] **workflow-author**: `dockerhub-docs.yml`, plus tests for it and for the secrets allowlist.
- [x] **container-author**: the dockerfile-docs skill documents the line, the choices and the fallback.
- [ ] **Owner**: after merge, run `Docker Hub docs` once. If it warns about categories, the `PATCH` doesn't set them. Then either set them in the UI, or capture the request the UI sends (browser dev tools, Network tab) so the script can use it.
- [ ] **Owner**: decide what to do with the stale `zippy1981/windows-nano-far` repository: delete it, or set its description to point at `windows-servercore-far`.

## Risks

- **The categories `PATCH` may be ignored or rejected.** Mitigation: verify-and-warn (decision 3) and the manual fallback.
- **Docker Hub may add or rename categories.** A renamed slug fails the publish-time check against the live list, as a warning, and the pinned test list needs updating with the date.
