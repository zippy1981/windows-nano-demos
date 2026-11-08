---
description: "Writes and maintains Architecture Decision Records under docs/adr/ in MADR style, and keeps the docs/adr/README.md index current. Use when a plan names an ADR, when a hard-to-reverse choice is made (base images, tagging, CI runners, publishing), or when asked to record, supersede, or deprecate a decision."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: deny
  webfetch: deny
  task: deny
---

# adr

Read and follow the role playbook in [`.claude/agents/adr.md`](../../.claude/agents/adr.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
