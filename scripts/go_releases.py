"""Report Go release lines in go-container.yml that need work, so new releases are noticed without guessing.

Go supports the two newest major releases (the Go release policy at go.dev/doc/devel/release). When a new line ships,
the older one stops being supported. This script finds the newest line from the release tags on golang/go, then reports:

- a supported line with no leg in the matrix
- a matrix leg whose line is behind the latest patch release
- a matrix leg whose line is no longer supported

It writes a Markdown report to --output, and the file stays empty when every leg is current. The Go release alert
workflow (.github/workflows/go-release-alert.yml) turns the report into one GitHub issue. Changing the matrix is still a
reviewed pull request (ADR 0007).

    uv run python scripts/go_releases.py [--workflow .github/workflows/go-container.yml] [--output go-release-alert.md]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from collections.abc import Callable
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "go-container.yml"
UPSTREAM = "golang/go"
# Go's policy: a major release is supported until two newer ones exist, so two lines are supported at any time
SUPPORTED_LINES = 2
# Upper bound on how many newer lines to look for, so a broken fetch can't loop forever
MAX_NEW_LINES = 5
TAG = re.compile(r"go(\d+)\.(\d+)(?:\.(\d+))?")

Series = tuple[int, int]
# Returns the tag names that start with a prefix such as "go1.27.", as in refs/tags/go1.27.3 -> go1.27.3
Fetch = Callable[[str], list[str]]


def github_tags(prefix: str) -> list[str]:
    """Tag names on golang/go that start with prefix, from the matching-refs API (one request, no pagination)."""
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "windows-nano-demos-go-releases"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:  # the workflow's token raises the rate limit from 60 requests an hour
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{UPSTREAM}/git/matching-refs/tags/{prefix}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return [ref["ref"].removeprefix("refs/tags/") for ref in json.load(response)]


def series_of(version: str) -> Series:
    """1.27.3 -> (1, 27)."""
    major, minor = (int(part) for part in version.split(".")[:2])
    return major, minor


def patches(series: Series, fetch: Fetch) -> list[int]:
    """The patch numbers released in one line. A final release such as go1.27.0 counts as patch 0."""
    found: list[int] = []
    for tag in fetch(f"go{series[0]}.{series[1]}."):
        match = TAG.fullmatch(tag)  # release candidates such as go1.27rc1 don't match: they have no patch dot
        if match and (int(match[1]), int(match[2])) == series:
            found.append(int(match[3] or 0))
    return found


def parse_matrix(workflow: Path) -> list[str]:
    """The go-version of every leg in the build job's matrix."""
    document = yaml.safe_load(workflow.read_text(encoding="utf-8"))
    include = document["jobs"]["build"]["strategy"]["matrix"]["include"]
    return [str(leg["go-version"]) for leg in include]


def findings(versions: list[str], fetch: Fetch) -> list[str]:
    """One line per change the matrix needs. Empty when every supported line has a current leg."""
    pinned: dict[Series, int] = {}
    for version in versions:
        series = series_of(version)
        pinned[series] = max(pinned.get(series, -1), int(version.split(".")[2]))
    newest = max(pinned)
    for _ in range(MAX_NEW_LINES):
        following = (newest[0], newest[1] + 1)
        if not patches(following, fetch):
            break
        newest = following
    supported = [(newest[0], newest[1] - line) for line in range(SUPPORTED_LINES)]

    lines: list[str] = []
    for series in supported:
        released = patches(series, fetch)
        if not released:
            continue
        latest = max(released)
        if series not in pinned:
            lines.append(
                f"Add a Go {series[0]}.{series[1]}.{latest} leg: that line is supported and CI doesn't build it."
            )
        elif pinned[series] < latest:
            lines.append(
                f"Bump the Go {series[0]}.{series[1]} legs from {series[0]}.{series[1]}.{pinned[series]} "
                f"to {series[0]}.{series[1]}.{latest}."
            )
    for series in sorted(pinned):
        if series not in supported:
            lines.append(
                f"Remove the Go {series[0]}.{series[1]}.{pinned[series]} leg: that line is no longer supported "
                f"(Go supports the {SUPPORTED_LINES} newest releases)."
            )
    return lines


def report(lines: list[str]) -> str:
    """The Markdown the alert issue shows. Empty when there is nothing to do, so the workflow can close its issue."""
    if not lines:
        return ""
    bullets = "\n".join(f"- {line}" for line in lines)
    return (
        "Go's release policy supports the two newest major releases, and CI builds the latest patch of each.\n\n"
        f"{bullets}\n\n"
        "To update: change the matrix in `.github/workflows/go-container.yml`, and if the newest line changed, the "
        "default `GO_VERSION` in `nano-server/nano-server-go/Dockerfile`. This issue closes on the next run once every "
        "leg is current.\n"
    )


def main(argv: list[str] | None = None, fetch: Fetch = github_tags, workflow: Path = WORKFLOW) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--workflow", type=Path, default=workflow, help="the Go container workflow to read")
    parser.add_argument("--output", type=Path, default=Path("go-release-alert.md"), help="where to write the report")
    args = parser.parse_args(argv)
    text = report(findings(parse_matrix(args.workflow), fetch))
    args.output.write_text(text, encoding="utf-8")
    print(text or "Every supported Go line in the matrix is current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
