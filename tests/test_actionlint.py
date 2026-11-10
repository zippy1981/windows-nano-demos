"""Tests for scripts/actionlint.py. Downloads are faked with in-memory archives, so these run offline."""

from __future__ import annotations

import hashlib
import io
import tarfile
import zipfile
from pathlib import Path

import actionlint as al
import pytest


def zip_archive(name: str, body: bytes) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zipped:
        zipped.writestr(name, body)
    return buffer.getvalue()


def tar_archive(name: str, body: bytes) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tarred:
        info = tarfile.TarInfo(name)
        info.size = len(body)
        tarred.addfile(info, io.BytesIO(body))
    return buffer.getvalue()


def releases(asset: str, archive: bytes, digest: str | None = None) -> al.Fetch:
    checksums = f"{digest or hashlib.sha256(archive).hexdigest()}  {asset}\nabc  other.zip\n".encode()

    def fetch(url: str) -> bytes:
        if url.endswith("_checksums.txt"):
            return checksums
        assert url == f"{al.RELEASES}/v{al.VERSION}/{asset}"
        return archive

    return fetch


@pytest.mark.parametrize(
    ("system", "machine", "expected"),
    [
        ("Windows", "AMD64", f"actionlint_{al.VERSION}_windows_amd64.zip"),
        ("Linux", "x86_64", f"actionlint_{al.VERSION}_linux_amd64.tar.gz"),
        ("Darwin", "arm64", f"actionlint_{al.VERSION}_darwin_arm64.tar.gz"),
    ],
)
def test_asset_name(system: str, machine: str, expected: str) -> None:
    assert al.asset_name(system, machine) == expected


@pytest.mark.parametrize(("system", "machine"), [("SunOS", "amd64"), ("Linux", "mips")])
def test_unsupported_platforms(system: str, machine: str) -> None:
    with pytest.raises(ValueError, match="no actionlint release"):
        al.asset_name(system, machine)


def test_cache_dir_uses_localappdata_on_windows(tmp_path: Path) -> None:
    assert al.cache_dir("Windows", {"LOCALAPPDATA": str(tmp_path)}) == tmp_path / "actionlint" / al.VERSION
    assert al.cache_dir("Linux", {}) == Path.home() / ".cache" / "actionlint" / al.VERSION


def test_windows_download_is_verified_extracted_and_cached(tmp_path: Path) -> None:
    asset = al.asset_name("Windows", "AMD64")
    fetch = releases(asset, zip_archive("actionlint.exe", b"exe"))
    environ = {"LOCALAPPDATA": str(tmp_path)}
    path = al.ensure_binary("Windows", "AMD64", environ, fetch)
    assert path.read_bytes() == b"exe"
    # Cached: a second call doesn't download
    assert al.ensure_binary("Windows", "AMD64", environ, lambda url: pytest.fail(url)) == path


def test_linux_download_extracts_from_the_tarball(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(al.Path, "home", lambda: tmp_path)
    asset = al.asset_name("Linux", "x86_64")
    path = al.ensure_binary("Linux", "x86_64", {}, releases(asset, tar_archive("actionlint", b"elf")))
    assert path == tmp_path / ".cache" / "actionlint" / al.VERSION / "actionlint"
    assert path.read_bytes() == b"elf"


def test_a_checksum_mismatch_is_refused(tmp_path: Path) -> None:
    asset = al.asset_name("Windows", "AMD64")
    fetch = releases(asset, zip_archive("actionlint.exe", b"exe"), digest="0" * 64)
    with pytest.raises(ValueError, match="checksum mismatch"):
        al.ensure_binary("Windows", "AMD64", {"LOCALAPPDATA": str(tmp_path)}, fetch)
    assert not (tmp_path / "actionlint" / al.VERSION / "actionlint.exe").exists()


def test_an_asset_missing_from_the_checksums_is_refused() -> None:
    with pytest.raises(ValueError, match="not in the release checksums"):
        al.expected_sha256("abc  other.zip\n", "actionlint.zip")


def test_a_tarball_entry_that_is_not_a_file_is_refused() -> None:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tarred:
        info = tarfile.TarInfo("actionlint")
        info.type = tarfile.DIRTYPE
        tarred.addfile(info)
    with pytest.raises(ValueError, match="is not in"):
        al.extract(buffer.getvalue(), "x.tar.gz", "actionlint")


def test_ensure_binary_defaults_to_this_machine(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(al.platform, "system", lambda: "Windows")
    monkeypatch.setattr(al.platform, "machine", lambda: "AMD64")
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    cached = tmp_path / "actionlint" / al.VERSION / "actionlint.exe"
    cached.parent.mkdir(parents=True)
    cached.write_bytes(b"exe")
    assert al.ensure_binary() == cached


def test_http_get_reads_the_body(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(al.urllib.request, "urlopen", lambda request, timeout: io.BytesIO(b"body"))
    assert al.http_get("https://example.com") == b"body"


def test_run_command_returns_the_exit_code(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(al.subprocess, "run", lambda command, cwd, check: type("R", (), {"returncode": 3})())
    assert al.run_command(["actionlint"]) == 3


def test_main_runs_oneline_on_the_given_files(capsys: pytest.CaptureFixture[str]) -> None:
    seen: list[list[str]] = []
    code = al.main([".github/workflows/a.yml"], lambda: Path("al"), lambda command: seen.append(command) or 0)
    assert code == 0
    assert seen == [["al", "-oneline", ".github/workflows/a.yml"]]
    assert "no findings" in capsys.readouterr().out


def test_main_passes_findings_through(capsys: pytest.CaptureFixture[str]) -> None:
    assert al.main([], lambda: Path("al"), lambda command: 1) == 1
    assert capsys.readouterr().out == ""


def test_main_print_path(capsys: pytest.CaptureFixture[str]) -> None:
    assert al.main(["--print-path"], lambda: Path("cache/al"), lambda command: pytest.fail("ran")) == 0
    assert capsys.readouterr().out.strip() == str(Path("cache/al"))


def test_main_reports_a_failed_download(capsys: pytest.CaptureFixture[str]) -> None:
    def broken() -> Path:
        raise OSError("offline")

    assert al.main([], broken, lambda command: 0) == 2
    assert "offline" in capsys.readouterr().err
