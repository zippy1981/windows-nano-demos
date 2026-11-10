"""Tests for scripts/local_image_check.py. docker and pwsh are faked, so these run offline."""

from __future__ import annotations

import sys
from pathlib import Path

import local_image_check as lic
import pytest
import refresh_matrix as rm

BASES = {version: f"zippy1981/nanoserver-base:ltsc{version}" for version in rm.WINDOWS_VERSIONS}
PHP = rm.ImageSpec("nano-server/nano-server-php", "windows-nano-php", "php-container.yml", BASES)
GO = rm.ImageSpec(
    "nano-server/nano-server-go",
    "windows-nano-go",
    "go-container.yml",
    BASES,
    build_args='{"GO_VERSION": "1.27.3", "CGO": "1"}',
    variant="go1.27.3-cgo",
)
GO_PLAIN = rm.ImageSpec("nano-server/nano-server-go", "windows-nano-go", "go-container.yml", BASES, variant="go1.27.3")


class FakeRun:
    """Records commands, writes a fake log for each, and fails the commands whose first words are in `fail`."""

    def __init__(self, fail: tuple[str, ...] = ()) -> None:
        self.commands: list[list[str]] = []
        self.fail = fail

    def __call__(self, command: list[str], log: Path) -> int:
        self.commands.append(command)
        failing = any(word in command for word in self.fail)
        log.write_text("step 1\nERROR: download failed\n" + "".join(f"line {n}\n" for n in range(40)), encoding="utf-8")
        return 1 if failing else 0


@pytest.mark.parametrize(
    ("context", "variant", "expected"),
    [
        ("nano-server/nano-server-php", "", PHP),
        ("nano-server\\nano-server-php\\", "", PHP),
        ("nano-server/nano-server-go", "go1.27.3-cgo", GO),
    ],
)
def test_find_spec(context: str, variant: str, expected: rm.ImageSpec) -> None:
    assert lic.find_spec([PHP, GO, GO_PLAIN], context, variant) == expected


@pytest.mark.parametrize(
    ("context", "variant", "message"),
    [
        ("nano-server/nano-server-nope", "", "no workflow builds"),
        ("nano-server/nano-server-go", "", "several variants; pass --variant"),
        ("nano-server/nano-server-go", "go9", "has no variant go9"),
    ],
)
def test_find_spec_errors(context: str, variant: str, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        lic.find_spec([PHP, GO, GO_PLAIN], context, variant)


def test_build_command_matches_ci() -> None:
    assert lic.build_command(GO, "2022", "t:2022") == [
        "docker", "build", "--memory", "4g",
        "--build-arg", "WINDOWS_VERSION=2022",
        "--build-arg", "BASE_IMAGE=zippy1981/nanoserver-base:ltsc2022",
        "--build-arg", "GO_VERSION=1.27.3",
        "--build-arg", "CGO=1",
        "-t", "t:2022", "nano-server/nano-server-go",
    ]  # fmt: skip


def test_build_command_refuses_a_version_the_image_skips() -> None:
    narrow = rm.ImageSpec("x", "x", "x.yml", {"2025": BASES["2025"]})
    with pytest.raises(ValueError, match="doesn't build for Windows 2019"):
        lic.build_command(narrow, "2019", "t")


def test_summary_keeps_errors_and_the_tail(tmp_path: Path) -> None:
    log = tmp_path / "build.log"
    log.write_text("a\nERROR one\nb\nc\nd\n", encoding="utf-8")
    assert lic.summary(log, 2) == ["    ERROR one", "    c", "    d"]


def test_a_passing_check_builds_tests_and_cleans_up(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    run = FakeRun()
    assert lic.check(PHP, "2025", "lic1-", tmp_path, False, run) == 0
    assert [command[:2] for command in run.commands] == [
        ["docker", "build"],
        ["pwsh", "-NoProfile"],
        ["pwsh", "-NoProfile"],
    ]
    assert run.commands[1][-3:] == [
        "nano-server/nano-server-php/smoke-test.ps1",
        "-Image",
        "lic1-windows-nano-php:2025",
    ]
    assert run.commands[2][-2:] == ["-Prefix", "lic1-"]
    out = capsys.readouterr().out
    assert "build ok" in out and "smoke test ok" in out and "cleanup ok" in out


def test_a_failed_build_prints_a_summary_and_still_cleans_up(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    run = FakeRun(fail=("build",))
    assert lic.check(PHP, "2025", "lic1-", tmp_path, False, run) == 1
    assert len(run.commands) == 2  # build, cleanup
    out = capsys.readouterr().out
    assert "build FAILED" in out and "ERROR: download failed" in out and "line 39" in out and "line 5\n" not in out


def test_a_failed_smoke_test_is_reported(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    run = FakeRun(fail=("nano-server/nano-server-php/smoke-test.ps1",))
    assert lic.check(PHP, "2025", "lic1-", tmp_path, False, run) == 1
    assert "smoke test FAILED" in capsys.readouterr().out


def test_keep_skips_cleanup(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    run = FakeRun()
    assert lic.check(PHP, "2025", "lic1-", tmp_path, True, run) == 0
    assert len(run.commands) == 2
    assert "Remove-DockerArtifacts.ps1 -Prefix lic1-" in capsys.readouterr().out


def test_a_failed_cleanup_is_reported(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    lic.check(PHP, "2025", "lic1-", tmp_path, False, FakeRun(fail=("scripts/Remove-DockerArtifacts.ps1",)))
    assert "cleanup FAILED" in capsys.readouterr().out


def test_main_uses_the_repo_workflows(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    run = FakeRun()
    logs = tmp_path / "logs"
    code = lic.main(["nano-server/nano-server-php", "--version", "2022", "--prefix", "Test-", "--logs", str(logs)], run)
    assert code == 0
    assert run.commands[0][-3:] == ["-t", "test-windows-nano-php:2022", "nano-server/nano-server-php"]
    assert (logs / "build.log").is_file()


def test_main_defaults_to_a_temporary_log_dir(capsys: pytest.CaptureFixture[str]) -> None:
    assert lic.main(["nano-server/nano-server-php"], FakeRun()) == 0
    assert "logs in" in capsys.readouterr().out


def test_main_reports_a_bad_folder(capsys: pytest.CaptureFixture[str]) -> None:
    assert lic.main(["nano-server/nano-server-nope"], FakeRun()) == 2
    assert "no workflow builds" in capsys.readouterr().err


def test_run_logged_writes_output_and_returns_the_code(tmp_path: Path) -> None:
    log = tmp_path / "out.log"
    assert lic.run_logged([sys.executable, "-c", "print('hi'); raise SystemExit(3)"], log) == 3
    assert log.read_text(encoding="utf-8").strip() == "hi"
