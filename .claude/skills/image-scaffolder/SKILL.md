---
name: image-scaffolder
description: Scaffold a new Nano Server image folder and its caller workflow with scripts/New-NanoServerImage.ps1. Use when asked to add a new container image or demo, or when windows-demo-scaffolder starts a new stack.
---

# Image scaffolder

Call `scripts/New-NanoServerImage.ps1` instead of writing a new image folder by
hand. It creates the folder, `Dockerfile`, `build.cmd`, `README.md` and the
workflow that calls the shared build workflow. Replace the generated placeholders
with the real artifact afterwards.

## Run it

From the repository root:

```powershell
./scripts/New-NanoServerImage.ps1 -Name <name> -Url <artifact-url>
```

For a versioned artifact URL, put the exact version in `-VersionString`:

```powershell
./scripts/New-NanoServerImage.ps1 -Name ripgrep `
    -Url https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip `
    -VersionString 14.1.1
```

The main options:

- `-Name` is mandatory, lowercase kebab-case. It produces `nano-server/nano-server-<name>`
  and the image `windows-nano-<name>`.
- `-Url` defaults to a placeholder. Percent-delimited tokens such as
  `%MINGIT_RELEASE%` are allowed and passed through for cmd to expand in the
  Dockerfile. `-VersionString` replaces that exact version substring in the URL
  with a Docker build argument.
- `-ExtractionTool` defaults to `tar.exe`. Use `7z.exe` for a Deflate64 ZIP that
  tar cannot read, or pass `-ExtractionArguments` for another extractor.
- `-WhatIf` previews the files. `-Force` overwrites an existing folder or workflow,
  so only use it when the user explicitly asks you to replace existing work.

## What it writes

- `nano-server/nano-server-<name>/Dockerfile`
- `nano-server/nano-server-<name>/build.cmd`
- `nano-server/nano-server-<name>/README.md`
- `.github/workflows/<name>-container.yml`, which calls
  `.github/workflows/build-windows-image.yml` with the new context and image.

The generated Dockerfile follows the `WINDOWS_VERSION`/`BASE_IMAGE` convention,
builds with `--memory 4g`, downloads before extracting, and uses the standard
ContainerUser entry point. The workflow has the per-pull-request concurrency
group and the path filters the repo expects.

## After it runs

1. Replace the placeholder download and extraction commands with the real install.
2. Add and exercise `smoke-test.ps1`; the shared workflow runs it.
3. Add the image to the root `README.md` image list.
4. Review the generated workflow, then hand further Dockerfile changes to
   `container-author` and workflow changes to `workflow-author`.
5. Run `./scripts/Invoke-RepoScriptAnalyzer.ps1`, `uv run pytest`, and
   `npx -y markdownlint-cli --dot '**/*.md'`.

Do not add `.gitignore`, the root README row, or unrelated files with the
generator; those stay manual review steps.
