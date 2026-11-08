"""OpenCode mirrors the Claude Code agents and skills (AGENTS.md, "OpenCode in this repo").

`opencode.json` registers the project skill folders. `.opencode/agent/<name>.md` is a thin subagent
wrapper over `.claude/agents/<name>.md`: the same description, subagent mode, and permissions that
mirror the playbook's Claude tools.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
import yaml
from repo_conventions import REPO_ROOT

CONFIG = REPO_ROOT / "opencode.json"
CLAUDE_AGENTS = REPO_ROOT / ".claude" / "agents"
OPENCODE_AGENTS = REPO_ROOT / ".opencode" / "agent"
SKILL_ROOTS = (REPO_ROOT / ".claude" / "skills", REPO_ROOT / ".agents" / "skills")

# Claude tool names map to the OpenCode permission each one needs. Write and Edit share `edit`, and
# Bash and PowerShell share `bash` (which runs pwsh on the Windows host).
TOOL_PERMISSIONS = {
    "Read": "read",
    "Glob": "glob",
    "Grep": "grep",
    "Write": "edit",
    "Edit": "edit",
    "Bash": "bash",
    "PowerShell": "bash",
    "WebFetch": "webfetch",
    "Agent": "task",
}
MANAGED_PERMISSIONS = ("read", "glob", "grep", "edit", "bash", "webfetch", "task")


def front_matter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n"), f"{path.name} must start with YAML front matter"
    data = yaml.safe_load(text.split("---", 2)[1])
    assert isinstance(data, dict), f"{path.name} front matter must be a mapping"
    return data


def load_config() -> dict[str, Any]:
    data = json.loads(CONFIG.read_text(encoding="utf-8"))
    assert isinstance(data, dict), "opencode.json must be a JSON object"
    return data


def claude_agent_names() -> list[str]:
    return sorted(path.stem for path in CLAUDE_AGENTS.glob("*.md") if path.name != "README.md")


def opencode_agent_names() -> list[str]:
    return sorted(path.stem for path in OPENCODE_AGENTS.glob("*.md"))


def skills() -> list[Path]:
    """One SKILL.md per skill name. `.claude/skills/github-issues` is a symlink to `.agents/skills`."""
    found: dict[str, Path] = {}
    for root in SKILL_ROOTS:
        for path in sorted(root.glob("*/SKILL.md")):
            found.setdefault(path.parent.name, path)
    return [found[name] for name in sorted(found)]


def test_config_declares_the_schema() -> None:
    assert load_config()["$schema"] == "https://opencode.ai/config.json"


def test_config_registers_every_skill_folder() -> None:
    registered = {str((REPO_ROOT / path).resolve()) for path in load_config()["skills"]["paths"]}
    expected = {str(path.resolve()) for path in SKILL_ROOTS}
    assert registered == expected, "opencode.json skills.paths must be .claude/skills and .agents/skills"


@pytest.mark.parametrize("skill", skills(), ids=lambda path: path.parent.name)
def test_every_skill_has_what_opencode_needs(skill: Path) -> None:
    data = front_matter(skill)
    assert data.get("name") == skill.parent.name, f"{skill}: the skill name must match its folder"
    assert data.get("description"), f"{skill}: OpenCode hides a skill that has no description"


def test_every_claude_agent_has_an_opencode_wrapper() -> None:
    assert opencode_agent_names() == claude_agent_names(), (
        "add .opencode/agent/<name>.md for every .claude/agents/<name>.md, or remove the stale wrapper"
    )


@pytest.mark.parametrize("name", claude_agent_names())
def test_opencode_wrapper_mirrors_the_claude_playbook(name: str) -> None:
    playbook = CLAUDE_AGENTS / f"{name}.md"
    wrapper = OPENCODE_AGENTS / f"{name}.md"
    data = front_matter(wrapper)
    assert data.get("mode") == "subagent", f"{name}: OpenCode agents in this repo are subagents"
    assert data.get("description") == front_matter(playbook).get("description"), (
        f"{name}: keep the wrapper description identical to .claude/agents/{name}.md"
    )
    assert f".claude/agents/{name}.md" in wrapper.read_text(encoding="utf-8"), (
        f"{name}: the wrapper must point at its .claude/agents playbook"
    )


@pytest.mark.parametrize("name", claude_agent_names())
def test_opencode_wrapper_permissions_mirror_the_claude_tools(name: str) -> None:
    tools = front_matter(CLAUDE_AGENTS / f"{name}.md")["tools"].split(", ")
    allowed = {TOOL_PERMISSIONS[tool] for tool in tools}
    permission = front_matter(OPENCODE_AGENTS / f"{name}.md")["permission"]
    for key in MANAGED_PERMISSIONS:
        expected = "allow" if key in allowed else "deny"
        assert permission.get(key) == expected, (
            f"{name}: set permission.{key} to {expected} to mirror tools: {tools}"
        )
