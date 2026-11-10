"""The mechanical half of the governance audit (.claude/agents/governance.md): agent definitions and their README
table, the skills and agents the playbooks name, the ADR index, and image READMEs. With these in CI, the
governance-scan skill hands the auditor only the failures, and the auditor spends its effort on judgement.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import pytest
import yaml
from repo_conventions import REPO_ROOT

AGENTS = REPO_ROOT / ".claude" / "agents"
SKILL_ROOTS = (REPO_ROOT / ".claude" / "skills", REPO_ROOT / ".agents" / "skills")
ADR_DIR = REPO_ROOT / "docs" / "adr"
MODELS = {"haiku", "sonnet", "opus"}
# Reviewers and auditors can't change anything (.claude/agents/README.md, "How tools were chosen")
READ_ONLY_AGENTS = {"governance", "windows-dockerfile-reviewer"}
WRITE_OR_SHELL = {"Write", "Edit", "Bash", "PowerShell"}


def front_matter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n"), f"{path.name} must start with YAML front matter"
    return yaml.safe_load(text.split("---", 2)[1])


def agent_files() -> list[Path]:
    return sorted(path for path in AGENTS.glob("*.md") if path.name != "README.md")


def tools(data: dict[str, Any]) -> list[str]:
    return [tool.strip() for tool in str(data.get("tools", "")).split(",") if tool.strip()]


def readme_rows() -> dict[str, tuple[str, list[str]]]:
    """Agent name -> (model, tools) from the table in .claude/agents/README.md."""
    rows = {}
    for line in (AGENTS / "README.md").read_text(encoding="utf-8").splitlines():
        match = re.match(r"\| `([a-z0-9-]+)` \|.*\| (\w+) \| ([^|]+) \|$", line)
        if match:
            rows[match[1]] = (match[2], [tool.strip() for tool in match[3].split(",")])
    return rows


def skill_names() -> set[str]:
    return {path.parent.name for root in SKILL_ROOTS for path in root.glob("*/SKILL.md")}


def agent_names() -> set[str]:
    return {path.stem for path in agent_files()}


@pytest.mark.parametrize("path", agent_files(), ids=lambda path: path.stem)
class TestAgentDefinition:
    def test_has_the_required_fields(self, path: Path) -> None:
        data = front_matter(path)
        missing = [key for key in ("name", "description", "tools", "model") if not data.get(key)]
        assert not missing, f"{path.name} front matter lacks {missing}; an agent without tools gets every tool"

    def test_name_matches_the_file(self, path: Path) -> None:
        assert front_matter(path)["name"] == path.stem

    def test_model_is_a_claude_tier(self, path: Path) -> None:
        assert front_matter(path)["model"] in MODELS

    def test_readme_row_matches(self, path: Path) -> None:
        rows = readme_rows()
        assert path.stem in rows, f"add {path.stem} to the table in .claude/agents/README.md"
        data = front_matter(path)
        assert rows[path.stem] == (data["model"], tools(data)), "README model and tools must match the front matter"

    def test_named_skills_exist(self, path: Path) -> None:
        named = set(re.findall(r"`([a-z0-9-]+)` skill", path.read_text(encoding="utf-8")))
        assert named <= skill_names(), f"{path.name} names skills that don't exist: {sorted(named - skill_names())}"

    def test_named_agents_exist(self, path: Path) -> None:
        named = set(re.findall(r"`([a-z0-9-]+)` agent\b", path.read_text(encoding="utf-8")))
        assert named <= agent_names(), (
            f"{path.name} hands off to agents that don't exist: {sorted(named - agent_names())}"
        )


@pytest.mark.parametrize("name", sorted(READ_ONLY_AGENTS))
def test_reviewers_cannot_change_files(name: str) -> None:
    granted = set(tools(front_matter(AGENTS / f"{name}.md"))) & WRITE_OR_SHELL
    assert not granted, f"{name} is read-only but has {sorted(granted)}"


def test_readme_lists_no_agent_that_does_not_exist() -> None:
    assert set(readme_rows()) <= agent_names()


def adr_files() -> list[Path]:
    return sorted(ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md"))


def adr_index() -> dict[str, tuple[str, str]]:
    """File name -> (number, status) from docs/adr/README.md."""
    rows = {}
    for line in (ADR_DIR / "README.md").read_text(encoding="utf-8").splitlines():
        match = re.match(r"\| (\d{4}) \| \[[^\]]+\]\(([^)]+)\) \| ([^|]+) \|", line)
        if match:
            rows[match[2]] = (match[1], match[3].strip())
    return rows


@pytest.mark.parametrize("path", adr_files(), ids=lambda path: path.name[:4])
def test_adr_is_indexed_with_its_status(path: Path) -> None:
    index = adr_index()
    assert path.name in index, f"add {path.name} to docs/adr/README.md"
    number, status = index[path.name]
    assert number == path.name[:4]
    declared = re.search(r"^- Status: (\w+)", path.read_text(encoding="utf-8"), re.MULTILINE)
    assert declared, f"{path.name} has no '- Status:' line"
    assert status.split()[0] == declared[1], f"docs/adr/README.md says {status}, {path.name} says {declared[1]}"


def test_adr_index_links_only_existing_records() -> None:
    assert {name for name in adr_index() if not (ADR_DIR / name).is_file()} == set()


def test_adr_numbers_are_unique() -> None:
    numbers = [path.name[:4] for path in adr_files()]
    assert len(numbers) == len(set(numbers))


def image_folders() -> list[Path]:
    return sorted(
        path.parent for root in ("nano-server", "server-core") for path in (REPO_ROOT / root).glob("*/Dockerfile")
    )


@pytest.mark.parametrize("folder", image_folders(), ids=lambda folder: folder.name)
def test_image_has_a_readme_linked_from_the_root_readme(folder: Path) -> None:
    assert (folder / "README.md").is_file(), f"{folder.name} has no README.md"
    link = f"({folder.relative_to(REPO_ROOT).as_posix()}/README.md)"
    assert link in (REPO_ROOT / "README.md").read_text(encoding="utf-8"), f"the root README doesn't link {link}"
