"""No script pipes a download into tar (issue #71).

libarchive on Windows silently drops about the first 64 KB of a zip read from a pipe, and exits 0
(zippy1981/windows-nano-baseimages#8). Windows' own tar.exe skipped files the same way (it dropped brotlicommon.dll
from PHP's zip). Download to a file, then run `tar -xf <file>`.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from repo_conventions import REPO_ROOT, TAR_FROM_PIPE, script_files, tar_from_pipe_lines

SCRIPTS = script_files()


def test_script_files_exist() -> None:
    assert any(p.name == "Dockerfile" for p in SCRIPTS), "no Dockerfiles found"
    assert any(p.suffix == ".yml" for p in SCRIPTS), "no workflows found"


@pytest.mark.parametrize("path", SCRIPTS, ids=lambda p: p.relative_to(REPO_ROOT).as_posix())
def test_does_not_pipe_into_tar(path: Path) -> None:
    hits = tar_from_pipe_lines(path.read_text(encoding="utf-8", errors="replace"))
    assert not hits, (
        f"{path.relative_to(REPO_ROOT).as_posix()} pipes into tar, which silently drops files from zips on Windows "
        "(zippy1981/windows-nano-baseimages#8). Download to a file and run tar -xf <file>: "
        + "; ".join(f"line {n}: {line}" for n, line in hits)
    )


@pytest.mark.parametrize(
    "line",
    [
        "curl -fsSL https://example.com/a.zip | tar -xf - -C C:\\",
        "curl.exe -L $url|tar xf -",
        "RUN curl -fsSL %URL% | tar.exe -xf -",
        'Invoke-WebRequest $u -OutFile - | & "C:\\tools\\bin\\tar.exe" -xf -',
        "curl -sL $u | C:\\Windows\\System32\\tar.exe -x",
        "curl -sL $u | bsdtar -xf -",
        "curl -sL $u | 'tar' -xf -",
        "curl -sL $u | TAR -xf -",
        "cat a.tar.gz | tar",
    ],
)
def test_rule_catches(line: str) -> None:
    assert TAR_FROM_PIPE.search(line), f"the rule should catch: {line}"


@pytest.mark.parametrize(
    "line",
    [
        "curl -fsSLo C:\\dl\\a.zip https://example.com/a.zip && tar -xf C:\\dl\\a.zip -C C:\\",
        "tar -cf - . | gzip > out.tar.gz",
        "Get-ChildItem | Where-Object Name -like '*.tar'",
        "echo foo | target.exe",
        "curl -fsSL https://getcomposer.org/installer | php -- --install-dir=C:\\php",
        "ls | star -x",
        "ls | tar_helper.ps1",
    ],
)
def test_rule_allows(line: str) -> None:
    assert not TAR_FROM_PIPE.search(line), f"the rule should allow: {line}"


@pytest.mark.parametrize(
    "text",
    [
        "# curl | tar -xf - drops files, so download first",
        "    # curl | tar -xf - drops files",
        "rem curl | tar -xf -",
        "REM curl | tar -xf -",
        ":: curl | tar -xf -",
    ],
)
def test_comment_lines_are_skipped(text: str) -> None:
    assert tar_from_pipe_lines(text) == []


def test_reports_line_numbers() -> None:
    assert tar_from_pipe_lines("@echo off\r\ncurl -L x | tar -xf -\r\n") == [(2, "curl -L x | tar -xf -")]
