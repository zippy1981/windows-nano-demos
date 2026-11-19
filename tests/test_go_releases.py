"""Tests for scripts/go_releases.py. Upstream tags are faked, so these run offline."""

from __future__ import annotations

import io
import json
from pathlib import Path

import go_releases as gr
import pytest

WORKFLOW = "go-container.yml"


def fake_tags(*tags: str):
    """A fetch that answers a prefix such as go1.27. with the tags that start with it."""

    def fetch(prefix: str) -> list[str]:
        return [tag for tag in tags if tag.startswith(prefix)]

    return fetch


def write_matrix(path: Path, versions: list[str]) -> Path:
    legs = "".join(f"\n          - {{go-version: '{version}', cgo: '0'}}" for version in versions)
    path.write_text(
        "jobs:\n  build:\n    strategy:\n      matrix:\n        include:" + legs + "\n",
        encoding="utf-8",
    )
    return path


class TestSeriesAndPatches:
    def test_series_of_a_version(self) -> None:
        assert gr.series_of("1.27.3") == (1, 27)

    def test_patches_only_count_the_requested_line(self) -> None:
        fetch = fake_tags("go1.27.0", "go1.27.3", "go1.26.10", "go1.28.0")
        assert sorted(gr.patches((1, 27), fetch)) == [0, 3]

    def test_release_candidates_have_no_patch_and_are_ignored(self) -> None:
        assert gr.patches((1, 28), fake_tags("go1.28rc1", "go1.28beta1")) == []

    def test_a_final_release_without_a_patch_number_counts_as_zero(self) -> None:
        assert gr.patches((1, 28), fake_tags("go1.28.0")) == [0]


class TestFindings:
    def test_current_matrix_has_nothing_to_report(self) -> None:
        fetch = fake_tags("go1.27.3", "go1.26.10")
        assert gr.findings(["1.27.3", "1.26.10"], fetch) == []

    def test_a_new_patch_bumps_its_line(self) -> None:
        fetch = fake_tags("go1.27.3", "go1.27.4", "go1.26.10")
        assert gr.findings(["1.27.3", "1.26.10"], fetch) == ["Bump the Go 1.27 legs from 1.27.3 to 1.27.4."]

    def test_a_new_line_needs_a_leg_and_retires_the_oldest(self) -> None:
        fetch = fake_tags("go1.28.0", "go1.27.3", "go1.26.10")
        assert gr.findings(["1.27.3", "1.26.10"], fetch) == [
            "Add a Go 1.28.0 leg: that line is supported and CI doesn't build it.",
            "Remove the Go 1.26.10 leg: that line is no longer supported (Go supports the 2 newest releases).",
        ]

    def test_two_new_lines_are_found_in_a_row(self) -> None:
        fetch = fake_tags("go1.29.1", "go1.28.0", "go1.27.3")
        assert gr.findings(["1.27.3"], fetch) == [
            "Add a Go 1.29.1 leg: that line is supported and CI doesn't build it.",
            "Add a Go 1.28.0 leg: that line is supported and CI doesn't build it.",
            "Remove the Go 1.27.3 leg: that line is no longer supported (Go supports the 2 newest releases).",
        ]

    def test_a_supported_line_missing_from_the_matrix_is_added(self) -> None:
        fetch = fake_tags("go1.27.3", "go1.26.10")
        assert gr.findings(["1.27.3"], fetch) == [
            "Add a Go 1.26.10 leg: that line is supported and CI doesn't build it.",
        ]

    def test_a_cgo_leg_on_the_same_line_is_one_pin(self) -> None:
        fetch = fake_tags("go1.27.3", "go1.26.10")
        assert gr.findings(["1.27.3", "1.27.3", "1.26.10"], fetch) == []

    def test_an_unsupported_line_is_removed_even_without_upstream_tags(self) -> None:
        fetch = fake_tags("go1.27.3", "go1.26.10")
        assert gr.findings(["1.27.3", "1.26.10", "1.25.14"], fetch) == [
            "Remove the Go 1.25.14 leg: that line is no longer supported (Go supports the 2 newest releases).",
        ]

    def test_a_supported_line_with_no_tags_is_skipped(self) -> None:
        # The older line is only checked against the matrix when upstream has tags for it
        fetch = fake_tags("go1.27.3")
        assert gr.findings(["1.27.3"], fetch) == []

    def test_newer_lookahead_stops_at_the_cap(self) -> None:
        # Every line "exists" forever, so the search must stop at MAX_NEW_LINES instead of looping
        def endless(prefix: str) -> list[str]:
            return [prefix + "0"]

        assert gr.findings(["1.27.3"], endless) == [
            "Add a Go 1.32.0 leg: that line is supported and CI doesn't build it.",
            "Add a Go 1.31.0 leg: that line is supported and CI doesn't build it.",
            "Remove the Go 1.27.3 leg: that line is no longer supported (Go supports the 2 newest releases).",
        ]


class TestReport:
    def test_no_findings_means_an_empty_report(self) -> None:
        assert gr.report([]) == ""

    def test_findings_become_a_bulleted_report(self) -> None:
        text = gr.report(["Bump the Go 1.27 legs from 1.27.3 to 1.27.4."])
        assert "- Bump the Go 1.27 legs from 1.27.3 to 1.27.4." in text
        assert "go-container.yml" in text
        assert text.endswith("\n")


class TestParseMatrix:
    def test_reads_every_leg_in_order(self, tmp_path: Path) -> None:
        path = write_matrix(tmp_path / WORKFLOW, ["1.27.3", "1.26.10"])
        assert gr.parse_matrix(path) == ["1.27.3", "1.26.10"]

    def test_the_real_matrix_never_lists_more_lines_than_go_supports(self) -> None:
        versions = gr.parse_matrix(gr.WORKFLOW)
        assert versions, "go-container.yml has no matrix legs"
        assert len({gr.series_of(version) for version in versions}) <= gr.SUPPORTED_LINES


class TestGithubTags:
    def test_reads_tag_names_from_matching_refs(self, monkeypatch: pytest.MonkeyPatch) -> None:
        body = json.dumps([{"ref": "refs/tags/go1.27.3"}, {"ref": "refs/tags/go1.27.4"}]).encode()
        seen: dict[str, object] = {}

        def fake_urlopen(request, timeout):
            seen["url"] = request.full_url
            seen["headers"] = dict(request.header_items())
            return io.BytesIO(body)

        monkeypatch.setattr(gr.urllib.request, "urlopen", fake_urlopen)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        assert gr.github_tags("go1.27.") == ["go1.27.3", "go1.27.4"]
        assert seen["url"] == "https://api.github.com/repos/golang/go/git/matching-refs/tags/go1.27."
        assert "Authorization" not in seen["headers"]

    def test_sends_the_token_when_one_is_set(self, monkeypatch: pytest.MonkeyPatch) -> None:
        seen: dict[str, object] = {}

        def fake_urlopen(request, timeout):
            seen["headers"] = dict(request.header_items())
            return io.BytesIO(b"[]")

        monkeypatch.setattr(gr.urllib.request, "urlopen", fake_urlopen)
        monkeypatch.setenv("GITHUB_TOKEN", "t0ken")
        assert gr.github_tags("go1.28.") == []
        assert seen["headers"]["Authorization"] == "Bearer t0ken"


class TestMain:
    def test_writes_the_report_and_returns_zero(self, tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
        workflow = write_matrix(tmp_path / WORKFLOW, ["1.27.3"])
        output = tmp_path / "alert.md"
        code = gr.main(
            ["--workflow", str(workflow), "--output", str(output)],
            fetch=fake_tags("go1.27.4"),
        )
        assert code == 0
        assert "Bump the Go 1.27 legs from 1.27.3 to 1.27.4." in output.read_text(encoding="utf-8")
        assert "Bump" in capsys.readouterr().out

    def test_leaves_the_output_empty_when_current(self, tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
        workflow = write_matrix(tmp_path / WORKFLOW, ["1.27.3"])
        output = tmp_path / "alert.md"
        assert gr.main(["--workflow", str(workflow), "--output", str(output)], fetch=fake_tags("go1.27.3")) == 0
        assert output.read_text(encoding="utf-8") == ""
        assert "is current" in capsys.readouterr().out
