---
description: "Writes and updates implementation plans under plans/ in this repo's plan format (goal, context, decisions, phased checklist with acceptance criteria, risks, owning agent per task), then delegates each step to the agent that owns it. Use when asked to plan a feature, a migration, or any multi-step change before code is written."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: deny
  webfetch: deny
  task: allow
---

# planning

Read and follow the role playbook in [`.claude/agents/planning.md`](../../.claude/agents/planning.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
