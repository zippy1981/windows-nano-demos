"""Print a current-to-latest table for every tool version pinned in the Dockerfiles, so updating pins doesn't mean
reading release indexes (Node's index.json alone is hundreds of KB). Each upstream is fetched once, here, and only the
answer is printed.

    uv run python scripts/check_versions.py [--outdated] [--json] [--only NODE_VERSION,PHP_VERSION]

A pin is any `<NAME>_VERSION=<value>` in an ENV or ARG line, except WINDOWS_VERSION. Every pin needs an entry in
SOURCES; tests/test_check_versions.py fails when a Dockerfile adds one that doesn't have it.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
IMAGE_ROOTS = ("nano-server", "server-core")
# WINDOWS_VERSION is the base image (image-refresh.yml); PHP_VS_VERSION is the toolset the PHP row's note names
IGNORED_PINS = {"WINDOWS_VERSION", "PHP_VS_VERSION"}
PIN = re.compile(r"\b(?P<name>[A-Z][A-Z0-9_]*_VERSION)=(?P<value>\"[^\"]*\"|[^\s\"\\]+)")

# Pin name -> (kind, argument, note). The kinds are the fetchers in latest().
SOURCES: dict[str, tuple[str, str, str]] = {
    "GO_VERSION": ("go", "", ""),
    "XCADDY_VERSION": ("goproxy", "github.com/caddyserver/xcaddy", ""),
    "CADDY_VERSION": ("goproxy", "github.com/caddyserver/caddy/v2", ""),
    "CACHE_HANDLER_VERSION": ("goproxy", "github.com/caddyserver/cache-handler", ""),
    "SIMPLEFS_VERSION": ("goproxy", "github.com/darkweak/storages/simplefs", ""),
    "SEVENZIP_VERSION": ("github", "ip7z/7zip", ""),
    "NANO_VERSION": ("github", "okibcn/nano-for-windows", ""),
    "HELIX_VERSION": ("github", "helix-editor/helix", ""),
    "RUNNER_VERSION": ("github", "actions/runner", ""),
    "DOCKER_VERSION": (
        "index",
        "https://download.docker.com/win/static/stable/x86_64/|docker-(\\d+\\.\\d+\\.\\d+)\\.zip",
        "",
    ),
    "MINGIT_VERSION": ("github", "git-for-windows/git", "also update MINGIT_TAG (or MINGIT_RELEASE and MINGIT_BUILD)"),
    "MICROEDITOR_VERSION": ("github", "micro-editor/micro", "also update MICROEDITOR_PATH"),
    "LLVM_MINGW_VERSION": ("github", "mstorsjo/llvm-mingw", ""),
    "MYSQL_VERSION": ("tags", "mysql/mysql-server|mysql-{series}.", "newest in the pinned series"),
    "NODE_VERSION": ("node", "", "newest LTS"),
    "NPM_VERSION": ("npm", "npm", ""),
    "PHP_VERSION": ("php", "", "newest in the pinned series; update PHP_VS_VERSION to the toolset shown"),
    "PESTER_VERSION": ("psgallery", "Pester", ""),
    "PSSCRIPTANALYZER_VERSION": ("psgallery", "PSScriptAnalyzer", ""),
    "PLATYPS_VERSION": ("psgallery", "Microsoft.PowerShell.PlatyPS", ""),
    "PSREADLINE_VERSION": ("psgallery", "PSReadLine", ""),
    "PSRESOURCEGET_VERSION": ("psgallery", "Microsoft.PowerShell.PSResourceGet", ""),
    "RUSTUP_VERSION": ("rustup", "", ""),
    "RUST_VERSION": ("github", "rust-lang/rust", ""),
    "OPENSSH_VERSION": ("github", "PowerShell/Win32-OpenSSH", ""),
    "FAR_VERSION": ("far", "", "stable build; set FAR_BUILD and FAR_DATE as shown, and FAR_SHA256 from the download"),
    "STACKABLE_ODBC_VERSION": ("github", "stackabletech/stackable-odbc-sqlite", ""),
}

Fetch = Callable[[str, dict[str, str]], bytes]


@dataclass
class Pin:
    dockerfile: str
    name: str
    current: str


@dataclass
class Row:
    dockerfile: str
    name: str
    current: str
    latest: str
    status: str  # current, outdated, error or no source
    note: str = ""


def http_get(url: str, headers: dict[str, str]) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "windows-nano-demos-check-versions", **headers})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def find_pins(root: Path = REPO_ROOT) -> list[Pin]:
    """Every *_VERSION pin with a literal value, in Dockerfile order. `GO_VERSION=${GO_VERSION}` copies an ARG."""
    pins: list[Pin] = []
    for folder in IMAGE_ROOTS:
        for path in sorted((root / folder).glob("*/Dockerfile")):
            seen: set[str] = set()
            for line in path.read_text(encoding="utf-8").splitlines():
                if line.lstrip().startswith("#"):
                    continue
                for match in PIN.finditer(line):
                    name, value = match["name"], match["value"].strip("'\"")
                    if name in IGNORED_PINS or "$" in value or name in seen:
                        continue
                    seen.add(name)
                    pins.append(Pin(path.relative_to(root).as_posix(), name, value))
    return pins


def numbers(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def compare(current: str, latest: str) -> str:
    """Compare as many numeric parts as both have, so a pin of 2.56.0 matches release 2.56.0.4."""
    have, want = numbers(current), numbers(latest)
    width = min(len(have), len(want))
    return "outdated" if want[:width] > have[:width] else "current"


def series(current: str) -> str:
    return ".".join(str(part) for part in numbers(current)[:2])


def github_headers() -> dict[str, str]:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    return {"Authorization": f"Bearer {token}"} if token else {}


def latest(kind: str, argument: str, current: str, fetch: Fetch) -> tuple[str, str]:
    """The newest upstream version for one source, and an extra note (such as PHP's toolset)."""
    if kind == "github":
        tag = json.loads(fetch(f"https://api.github.com/repos/{argument}/releases/latest", github_headers()))[
            "tag_name"
        ]
        if argument == "git-for-windows/git":  # v2.56.0.windows.4 -> 2.56.0.4, the MinGit file name
            return ".".join(str(part) for part in numbers(tag)), ""
        return re.sub(r"^(ci/)?v", "", tag), ""
    if kind == "tags":
        repo, prefix = argument.split("|")
        prefix = prefix.format(series=series(current))
        refs = json.loads(
            fetch(f"https://api.github.com/repos/{repo}/git/matching-refs/tags/{prefix}", github_headers())
        )
        versions = [ref["ref"].removeprefix(f"refs/tags/{prefix}") for ref in refs]
        return prefix.split("-")[-1] + max(versions, key=numbers), ""
    if kind == "goproxy":
        return json.loads(fetch(f"https://proxy.golang.org/{argument}/@latest", {}))["Version"], ""
    if kind == "go":
        releases = json.loads(fetch("https://go.dev/dl/?mode=json", {}))
        return next(r["version"].removeprefix("go") for r in releases if r.get("stable")), ""
    if kind == "node":
        releases = json.loads(fetch("https://nodejs.org/dist/index.json", {}))
        return next(r["version"].removeprefix("v") for r in releases if r.get("lts")), ""
    if kind == "npm":
        return json.loads(fetch(f"https://registry.npmjs.org/{argument}/latest", {}))["version"], ""
    if kind == "php":
        releases = json.loads(fetch("https://windows.php.net/downloads/releases/releases.json", {}))
        release = releases[series(current)]
        toolset = next((key.split("-")[1] for key in release if re.fullmatch(r"nts-vs\d+-x64", key)), "")
        newest = max(releases, key=numbers)
        extra = f"toolset {toolset}" + (
            f"; newer series {newest} exists" if numbers(newest) > numbers(series(current)) else ""
        )
        return release["version"], extra
    if kind == "psgallery":
        url = (
            "https://www.powershellgallery.com/api/v2/Packages()"
            f"?$filter=Id%20eq%20'{argument}'%20and%20IsLatestVersion&$select=Version"
        )
        match = re.search(r"<d:Version>([^<]+)</d:Version>", fetch(url, {}).decode("utf-8"))
        if not match:
            raise ValueError(f"no version for {argument} on the PowerShell Gallery")
        return match[1], ""
    if kind == "rustup":
        text = fetch("https://static.rust-lang.org/rustup/release-stable.toml", {}).decode("utf-8")
        return re.search(r"^version = '([^']+)'", text, re.MULTILINE)[1], ""  # type: ignore[index]
    if kind == "index":
        url, pattern = argument.split("|")
        found = re.findall(pattern, fetch(url, {}).decode("utf-8"))
        return max(found, key=numbers), ""
    if kind == "far":
        # The page lists stable builds before nightlies; GitHub's latest release is a nightly
        page = fetch("https://www.farmanager.com/download.php", {}).decode("utf-8")
        stable = page.split("Nightly builds")[0].split("Stable builds")[-1]
        match = re.search(r"Far30b(\d+)\.x64\.(\d+)\.7z", stable)
        if not match:
            raise ValueError("no stable x64 build on farmanager.com/download.php")
        return f"3.0.{match[1]}", f"FAR_BUILD={match[1]} FAR_DATE={match[2]}"
    raise ValueError(f"unknown source kind {kind}")


def check(pins: list[Pin], fetch: Fetch = http_get) -> list[Row]:
    rows: list[Row] = []
    cache: dict[tuple[str, str, str], tuple[str, str]] = {}
    for pin in pins:
        if pin.name not in SOURCES:
            rows.append(Row(pin.dockerfile, pin.name, pin.current, "", "no source", "add it to SOURCES"))
            continue
        kind, argument, note = SOURCES[pin.name]
        # Series-scoped sources (PHP, MySQL) depend on the pin; the rest are fetched once for every Dockerfile
        key = (kind, argument, series(pin.current) if kind in ("php", "tags") else "")
        try:
            if key not in cache:
                cache[key] = latest(kind, argument, pin.current, fetch)
            version, extra = cache[key]
        except (urllib.error.URLError, OSError, ValueError, KeyError, TypeError, StopIteration) as error:
            rows.append(Row(pin.dockerfile, pin.name, pin.current, "", "error", str(error)[:120]))
            continue
        notes = "; ".join(part for part in (extra, note) if part)
        rows.append(Row(pin.dockerfile, pin.name, pin.current, version, compare(pin.current, version), notes))
    return rows


def table(rows: list[Row]) -> str:
    if not rows:
        return "Every pin is current."
    lines = ["| Dockerfile | Pin | Current | Latest | Status | Note |", "| --- | --- | --- | --- | --- | --- |"]
    lines += [f"| {r.dockerfile} | {r.name} | {r.current} | {r.latest} | {r.status} | {r.note} |" for r in rows]
    return "\n".join(lines)


def main(argv: list[str] | None = None, fetch: Fetch = http_get, root: Path = REPO_ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--outdated", action="store_true", help="only rows that aren't current")
    parser.add_argument("--json", action="store_true", help="JSON instead of a Markdown table")
    parser.add_argument("--only", default="", help="comma-separated pin names")
    args = parser.parse_args(argv)
    only = {name for name in args.only.split(",") if name}
    pins = [pin for pin in find_pins(root) if not only or pin.name in only]
    rows = check(pins, fetch)
    if args.outdated:
        rows = [row for row in rows if row.status != "current"]
    print(json.dumps([asdict(row) for row in rows], indent=2) if args.json else table(rows))
    return 1 if any(row.status in ("error", "no source") for row in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
