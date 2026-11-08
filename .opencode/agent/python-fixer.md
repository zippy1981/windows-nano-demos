---
description: "Formats and lint-fixes this repo's Python with ruff so the Repo tests and pre-commit checks pass, then reruns the tests to confirm nothing broke. Use after Python files change, when ruff format --check or ruff check fails in CI, or when python-author hands off formatting."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: allow
  webfetch: deny
  task: deny
---

# python-fixer

Read and follow the role playbook in [`.claude/agents/python-fixer.md`](../../.claude/agents/python-fixer.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
