---
name: local-image-check
description: Build one image on this host the way CI does (same base image and build arguments from its caller workflow, --memory 4g), run its smoke-test.ps1, and remove what it created, printing a few lines instead of the build log. Use to check a Dockerfile change before pushing, for windows-container-builder and windows-container-tester, and instead of hand-running docker build, the smoke test and cleanup.
---

# Local image check

```pwsh
uv run python scripts/local_image_check.py nano-server/nano-server-php                   # Windows 2025
uv run python scripts/local_image_check.py nano-server/nano-server-go --variant go1.27.3-cgo --version 2022
```

Builds take minutes, so run it in the background (`run_in_background`) and wait for the notification. Don't poll. Build one Windows version at a time, not several in parallel.

What it does:

1. Finds the image's spec in its caller workflow (`refresh_matrix.discover_images`), so the base image, `base-image-overrides` and `build-args` match the CI leg. An image with several variants needs `--variant`. The error lists them.
2. Runs `docker build --memory 4g` with a tag under a unique prefix (default `lic<pid>-`, or `--prefix`).
3. Runs `<folder>/smoke-test.ps1 -Image <tag>`.
4. Always removes the tag with `scripts/Remove-DockerArtifacts.ps1 -Prefix <prefix>`, keeping parent layers for the build cache. Pass `--keep` to keep the image, for example to hand it to `windows-image-publisher`. It then prints the cleanup command to run later.

The output is a few lines: one each for the build, the smoke test and the cleanup. On a failure, it adds the error-looking lines and the last lines of that step. Full logs go to the directory it prints (or `--logs`). Read them only if the summary isn't enough, and with `Select-String`, not whole.

If the build fails for environmental reasons (the engine is in Linux mode, a base is newer than the host, the disk is full), use the `container-host-check` skill.
