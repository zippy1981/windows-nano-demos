---
description: "Writes Python 3 tools and tests for this repo, managed with uv, including the convention tests under tests/ that check workflows, Dockerfiles and build scripts (ADR 0010, 0011). Use when asked for a Python script, when a convention changes and its test must change with it, or when a task such as parsing YAML or JSON is clearer in Python than in PowerShell."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: allow
  webfetch: deny
  task: allow
---

# python-author

Read and follow the role playbook in [`.claude/agents/python-author.md`](../../.claude/agents/python-author.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
