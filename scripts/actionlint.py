"""Run actionlint on the workflows without hunting for it: the pinned release is downloaded once, checked against the
release's checksums file, and cached outside the repo. Output is one line per finding.

    uv run python scripts/actionlint.py [workflow files...]   # default: every file in .github/workflows
    uv run python scripts/actionlint.py --print-path           # where the binary is, downloading it if needed

The cache is %LOCALAPPDATA%/actionlint/<version> on Windows and ~/.cache/actionlint/<version> elsewhere.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import platform
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from collections.abc import Callable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VERSION = "1.7.12"
RELEASES = "https://github.com/rhysd/actionlint/releases/download"
ARCHES = {"amd64": "amd64", "x86_64": "amd64", "arm64": "arm64", "aarch64": "arm64"}

Fetch = Callable[[str], bytes]
Run = Callable[[list[str]], int]


def http_get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "windows-nano-demos-actionlint"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def asset_name(system: str, machine: str, version: str = VERSION) -> str:
    os_name = system.lower()
    if os_name not in ("windows", "linux", "darwin"):
        raise ValueError(f"no actionlint release for {system}")
    arch = ARCHES.get(machine.lower())
    if not arch:
        raise ValueError(f"no actionlint release for {machine}")
    extension = "zip" if os_name == "windows" else "tar.gz"
    return f"actionlint_{version}_{os_name}_{arch}.{extension}"


def cache_dir(system: str, environ: dict[str, str], version: str = VERSION) -> Path:
    if system.lower() == "windows" and environ.get("LOCALAPPDATA"):
        return Path(environ["LOCALAPPDATA"]) / "actionlint" / version
    return Path.home() / ".cache" / "actionlint" / version


def expected_sha256(checksums: str, asset: str) -> str:
    for line in checksums.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == asset:
            return parts[0]
    raise ValueError(f"{asset} is not in the release checksums")


def extract(archive: bytes, asset: str, binary: str) -> bytes:
    if asset.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
            return zipped.read(binary)
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tarred:
        member = tarred.extractfile(binary)
        if member is None:
            raise ValueError(f"{binary} is not in {asset}")
        return member.read()


def ensure_binary(
    system: str | None = None,
    machine: str | None = None,
    environ: dict[str, str] | None = None,
    fetch: Fetch = http_get,
) -> Path:
    """The cached binary, downloading and verifying the pinned release the first time."""
    system = system or platform.system()
    machine = machine or platform.machine()
    environ = dict(os.environ) if environ is None else environ
    binary = "actionlint.exe" if system.lower() == "windows" else "actionlint"
    path = cache_dir(system, environ) / binary
    if path.is_file():
        return path
    asset = asset_name(system, machine)
    archive = fetch(f"{RELEASES}/v{VERSION}/{asset}")
    checksums = fetch(f"{RELEASES}/v{VERSION}/actionlint_{VERSION}_checksums.txt").decode("utf-8")
    actual = hashlib.sha256(archive).hexdigest()
    if actual != expected_sha256(checksums, asset):
        raise ValueError(f"{asset} checksum mismatch: got {actual}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(extract(archive, asset, binary))
    path.chmod(0o755)
    return path


def run_command(command: list[str]) -> int:
    return subprocess.run(command, cwd=REPO_ROOT, check=False).returncode


def main(argv: list[str] | None = None, ensure: Callable[[], Path] = ensure_binary, run: Run = run_command) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*", help="workflow files; default every workflow")
    parser.add_argument("--print-path", action="store_true", help="print the binary's path and exit")
    args = parser.parse_args(argv)
    try:
        binary = ensure()
    except (OSError, ValueError) as error:
        print(f"actionlint: couldn't get v{VERSION}: {error}", file=sys.stderr)
        return 2
    if args.print_path:
        print(binary)
        return 0
    code = run([str(binary), "-oneline", *args.files])
    if code == 0:
        print(f"actionlint v{VERSION}: no findings")
    return code


if __name__ == "__main__":
    sys.exit(main())
