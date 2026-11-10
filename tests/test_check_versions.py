"""Tests for scripts/check_versions.py. Upstreams are faked, so these run offline."""

from __future__ import annotations

import io
import json
import urllib.error
from pathlib import Path

import check_versions as cv
import pytest

GITHUB = "https://api.github.com/repos"
RESPONSES: dict[str, bytes] = {
    f"{GITHUB}/ip7z/7zip/releases/latest": json.dumps({"tag_name": "26.06"}).encode(),
    f"{GITHUB}/micro-editor/micro/releases/latest": json.dumps({"tag_name": "v2.0.15"}).encode(),
    "https://www.farmanager.com/download.php": (
        b'<h2>Stable builds</h2><a href="files/Far30b6699.x64.20260614.7z">x64</a>'
        b'<h2>Nightly builds</h2><a href="files/Far30b6751.x64.20261110.7z">x64</a>'
    ),
    f"{GITHUB}/git-for-windows/git/releases/latest": json.dumps({"tag_name": "v2.57.0.windows.1"}).encode(),
    f"{GITHUB}/mysql/mysql-server/git/matching-refs/tags/mysql-8.4.": json.dumps(
        [{"ref": "refs/tags/mysql-8.4.9"}, {"ref": "refs/tags/mysql-8.4.13"}, {"ref": "refs/tags/mysql-8.4.11"}]
    ).encode(),
    "https://proxy.golang.org/github.com/caddyserver/caddy/v2/@latest": b'{"Version":"v2.11.9"}',
    "https://go.dev/dl/?mode=json": json.dumps(
        [{"version": "go1.28rc1", "stable": False}, {"version": "go1.27.3", "stable": True}]
    ).encode(),
    "https://nodejs.org/dist/index.json": json.dumps(
        [{"version": "v27.0.0", "lts": False}, {"version": "v26.13.0", "lts": "Krypton"}]
    ).encode(),
    "https://registry.npmjs.org/npm/latest": b'{"version":"12.2.2"}',
    "https://windows.php.net/downloads/releases/releases.json": json.dumps(
        {
            "8.5": {"version": "8.5.13", "nts-vs17-x64": {}, "ts-vs17-x64": {}},
            "8.6": {"version": "8.6.0", "nts-vs18-x64": {}},
        }
    ).encode(),
    "https://www.powershellgallery.com/api/v2/Packages()?$filter=Id%20eq%20'Pester'%20and%20IsLatestVersion&$select=Version": (
        b"<feed><entry><d:Version>6.2.0</d:Version></entry></feed>"
    ),
    "https://static.rust-lang.org/rustup/release-stable.toml": b"schema-version = '1'\nversion = '1.29.3'\n",
    "https://download.docker.com/win/static/stable/x86_64/": (
        b'<a href="docker-29.10.0.zip">docker-29.10.0.zip</a><a href="docker-29.9.3.zip">docker-29.9.3.zip</a>'
    ),
}


def fake_fetch(url: str, headers: dict[str, str]) -> bytes:
    if url not in RESPONSES:
        raise urllib.error.URLError(f"unexpected {url}")
    return RESPONSES[url]


@pytest.mark.parametrize("pin", cv.find_pins(), ids=lambda pin: f"{pin.dockerfile}:{pin.name}")
def test_every_dockerfile_pin_has_a_source(pin: cv.Pin) -> None:
    assert pin.name in cv.SOURCES, f"add {pin.name} to SOURCES in scripts/check_versions.py"


@pytest.mark.parametrize(
    ("name", "current", "expected"),
    [
        ("SEVENZIP_VERSION", "26.05", ("26.06", "outdated")),
        ("MICROEDITOR_VERSION", "2.0.15", ("2.0.15", "current")),
        ("FAR_VERSION", "3.0.6698", ("3.0.6699", "outdated")),
        ("MINGIT_VERSION", "2.56.0.4", ("2.57.0.1", "outdated")),
        ("MYSQL_VERSION", "8.4.11", ("8.4.13", "outdated")),
        ("CADDY_VERSION", "v2.11.9", ("v2.11.9", "current")),
        ("GO_VERSION", "1.27.3", ("1.27.3", "current")),
        ("NODE_VERSION", "26.13.0", ("26.13.0", "current")),
        ("NPM_VERSION", "12.2.1", ("12.2.2", "outdated")),
        ("PHP_VERSION", "8.5.12-1", ("8.5.13", "outdated")),
        ("PESTER_VERSION", "6.2.0", ("6.2.0", "current")),
        ("RUSTUP_VERSION", "1.29.3", ("1.29.3", "current")),
        ("DOCKER_VERSION", "29.9.3", ("29.10.0", "outdated")),
    ],
)
def test_each_source_kind(name: str, current: str, expected: tuple[str, str]) -> None:
    [row] = cv.check([cv.Pin("x/Dockerfile", name, current)], fake_fetch)
    assert (row.latest, row.status) == expected


def test_php_names_the_toolset_and_a_newer_series() -> None:
    [row] = cv.check([cv.Pin("x/Dockerfile", "PHP_VERSION", "8.5.12")], fake_fetch)
    assert row.note.startswith("toolset vs17; newer series 8.6 exists")


def test_far_reports_the_stable_build_not_the_nightly() -> None:
    [row] = cv.check([cv.Pin("x/Dockerfile", "FAR_VERSION", "3.0.6699")], fake_fetch)
    assert (row.latest, row.status) == ("3.0.6699", "current")
    assert row.note.startswith("FAR_BUILD=6699 FAR_DATE=20260614")


def test_far_without_a_stable_build_is_an_error() -> None:
    with pytest.raises(ValueError, match="no stable x64 build"):
        cv.latest("far", "", "3.0.1", lambda url, headers: b"<h2>Nightly builds</h2>Far30b1.x64.1.7z")


def test_a_short_pin_matches_a_longer_release() -> None:
    assert cv.compare("2.56.0", "2.56.0.4") == "current"
    assert cv.compare("2.56.0", "2.57.0.1") == "outdated"


def test_each_upstream_is_fetched_once() -> None:
    calls: list[str] = []

    def counting(url: str, headers: dict[str, str]) -> bytes:
        calls.append(url)
        return fake_fetch(url, headers)

    pins = [cv.Pin(f"{n}/Dockerfile", "MICROEDITOR_VERSION", "2.0.15") for n in "abc"]
    cv.check(pins, counting)
    assert len(calls) == 1


def test_failures_and_unknown_pins_become_rows() -> None:
    rows = cv.check([cv.Pin("x", "HELIX_VERSION", "1"), cv.Pin("x", "NEW_VERSION", "1")], fake_fetch)
    assert [row.status for row in rows] == ["error", "no source"]


def test_psgallery_without_a_version_is_an_error(monkeypatch: pytest.MonkeyPatch) -> None:
    with pytest.raises(ValueError, match="no version"):
        cv.latest("psgallery", "Nope", "1", lambda url, headers: b"<feed/>")


def test_an_unknown_kind_is_an_error() -> None:
    with pytest.raises(ValueError, match="unknown source kind"):
        cv.latest("ftp", "", "1", fake_fetch)


def test_http_get_sends_a_user_agent(monkeypatch: pytest.MonkeyPatch) -> None:
    seen = {}

    def urlopen(request, timeout):
        seen.update(request.headers)
        return io.BytesIO(b"body")

    monkeypatch.setattr(cv.urllib.request, "urlopen", urlopen)
    assert cv.http_get("https://example.com", {"X-A": "1"}) == b"body"
    assert seen["User-agent"] == "windows-nano-demos-check-versions" and seen["X-a"] == "1"


def test_github_uses_a_token_when_one_is_set(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    monkeypatch.setenv("GH_TOKEN", "t")
    assert cv.github_headers() == {"Authorization": "Bearer t"}
    monkeypatch.delenv("GH_TOKEN")
    assert cv.github_headers() == {}


def write_dockerfile(root: Path, folder: str, text: str) -> None:
    path = root / folder / "Dockerfile"
    path.parent.mkdir(parents=True)
    path.write_text(text, encoding="utf-8")


def test_find_pins_skips_comments_copies_and_ignored_names(tmp_path: Path) -> None:
    write_dockerfile(
        tmp_path,
        "nano-server/nano-server-x",
        "ARG WINDOWS_VERSION=2025\n# OLD_VERSION=1\nARG GO_VERSION=1.27.3\nENV GO_VERSION=${GO_VERSION} \\\n"
        '    MICROEDITOR_VERSION="2.0.15" \\\n    GO_VERSION=9\n',
    )
    assert cv.find_pins(tmp_path) == [
        cv.Pin("nano-server/nano-server-x/Dockerfile", "GO_VERSION", "1.27.3"),
        cv.Pin("nano-server/nano-server-x/Dockerfile", "MICROEDITOR_VERSION", "2.0.15"),
    ]


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    write_dockerfile(tmp_path, "nano-server/nano-server-a", "ENV MICROEDITOR_VERSION=2.0.15 SEVENZIP_VERSION=26.05\n")
    return tmp_path


def test_main_prints_a_table(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert cv.main([], fake_fetch, repo) == 0
    out = capsys.readouterr().out
    assert "| Pin |" in out and "SEVENZIP_VERSION | 26.05 | 26.06 | outdated" in out


def test_main_outdated_json_only(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert cv.main(["--outdated", "--json"], fake_fetch, repo) == 0
    assert [row["name"] for row in json.loads(capsys.readouterr().out)] == ["SEVENZIP_VERSION"]


def test_main_only_and_an_empty_result(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert cv.main(["--only", "MICROEDITOR_VERSION", "--outdated"], fake_fetch, repo) == 0
    assert capsys.readouterr().out.strip() == "Every pin is current."


def test_main_fails_when_a_lookup_fails(repo: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert cv.main([], lambda url, headers: (_ for _ in ()).throw(urllib.error.URLError("down")), repo) == 1
