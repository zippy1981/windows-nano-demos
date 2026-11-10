"""Build one image locally the way CI does, run its smoke test, and clean up, printing a few lines instead of the
build log. The base image and build arguments come from the image's caller workflow (refresh_matrix.discover_images),
so a local build matches the CI leg for that Windows version.

    uv run python scripts/local_image_check.py nano-server/nano-server-php [--version 2025] [--variant v] [--keep]

Everything it creates is tagged with a unique prefix (default lic<pid>-) and removed afterwards with
scripts/Remove-DockerArtifacts.ps1, because the Docker daemon is shared with the runners. Builds take minutes: run it
in the background. Full logs stay in the log directory it prints.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path

import refresh_matrix as rm

REPO_ROOT = Path(__file__).resolve().parent.parent
ERROR_LINE = re.compile(r"error|failed|exception|cannot|not found", re.IGNORECASE)

# A command and the file its output goes to -> exit code
Run = Callable[[list[str], Path], int]


def run_logged(command: list[str], log: Path) -> int:
    with log.open("w", encoding="utf-8", errors="replace") as out:
        return subprocess.run(command, cwd=REPO_ROOT, stdout=out, stderr=subprocess.STDOUT, check=False).returncode


def find_spec(specs: list[rm.ImageSpec], context: str, variant: str) -> rm.ImageSpec:
    context = context.replace("\\", "/").strip("/")
    matches = [spec for spec in specs if spec.context == context]
    if not matches:
        raise ValueError(f"no workflow builds {context} through build-windows-image.yml")
    if variant:
        matches = [spec for spec in matches if spec.variant == variant]
        if not matches:
            raise ValueError(f"{context} has no variant {variant}")
    elif len(matches) > 1:
        names = ", ".join(spec.variant for spec in matches)
        raise ValueError(f"{context} has several variants; pass --variant ({names})")
    return matches[0]


def build_command(spec: rm.ImageSpec, version: str, tag: str) -> list[str]:
    if version not in spec.bases:
        raise ValueError(f"{spec.context} doesn't build for Windows {version} ({', '.join(spec.bases)})")
    args = ["--build-arg", f"WINDOWS_VERSION={version}", "--build-arg", f"BASE_IMAGE={spec.bases[version]}"]
    for key, value in json.loads(spec.build_args).items():
        args += ["--build-arg", f"{key}={value}"]
    return ["docker", "build", "--memory", "4g", *args, "-t", tag, spec.context]


def summary(log: Path, tail: int) -> list[str]:
    """The error-looking lines plus the last few, deduplicated, so a failure needs no log reading."""
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    picked = [line for line in lines[:-tail] if ERROR_LINE.search(line)][-10:] + lines[-tail:]
    return [f"    {line}" for line in dict.fromkeys(picked)]


def check(spec: rm.ImageSpec, version: str, prefix: str, logs: Path, keep: bool, run: Run) -> int:
    tag = f"{prefix}{spec.image}:{version}".lower()
    print(f"{spec.context} for Windows {version} as {tag} (logs in {logs})")
    code = 1
    try:
        started = time.monotonic()
        build_log = logs / "build.log"
        if run(build_command(spec, version, tag), build_log):
            print(f"build FAILED after {time.monotonic() - started:.0f}s:")
            print("\n".join(summary(build_log, 30)))
            return code
        print(f"build ok in {time.monotonic() - started:.0f}s")
        smoke_log = logs / "smoke-test.log"
        smoke = ["pwsh", "-NoProfile", "-File", f"{spec.context}/smoke-test.ps1", "-Image", tag]
        if run(smoke, smoke_log):
            print("smoke test FAILED:")
            print("\n".join(summary(smoke_log, 20)))
            return code
        print("smoke test ok")
        code = 0
        return code
    finally:
        if keep:
            print(f"kept {tag}; remove it later with ./scripts/Remove-DockerArtifacts.ps1 -Prefix {prefix}")
        else:
            cleanup = ["pwsh", "-NoProfile", "-File", "scripts/Remove-DockerArtifacts.ps1", "-Prefix", prefix]
            print("cleanup ok" if run(cleanup, logs / "cleanup.log") == 0 else f"cleanup FAILED, see {logs}")


def main(argv: list[str] | None = None, run: Run = run_logged, root: Path = REPO_ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("context", help="image folder, such as nano-server/nano-server-php")
    parser.add_argument("--version", default="2025", choices=rm.WINDOWS_VERSIONS)
    parser.add_argument("--variant", default="", help="for images built as several variants")
    parser.add_argument("--prefix", default=f"lic{os.getpid()}-", help="tag prefix, at least 4 characters")
    parser.add_argument("--logs", type=Path, help="log directory (default: a new temporary one)")
    parser.add_argument("--keep", action="store_true", help="keep the image instead of removing it")
    args = parser.parse_args(argv)
    try:
        spec = find_spec(rm.discover_images(root), args.context, args.variant)
        build_command(spec, args.version, "check")
    except ValueError as error:
        print(f"local_image_check: {error}", file=sys.stderr)
        return 2
    logs = args.logs or Path(tempfile.mkdtemp(prefix="local-image-check-"))
    logs.mkdir(parents=True, exist_ok=True)
    return check(spec, args.version, args.prefix, logs, args.keep, run)


if __name__ == "__main__":
    sys.exit(main())
