---
description: "Writes PowerShell 7 scripts and modules for this repo (runner entrypoints, CI helper scripts, maintenance tasks) with Pester tests, clean under PSScriptAnalyzer. Use when a workflow step grows beyond a few lines, or when asked for a PowerShell script or module."
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

# powershell-author

Read and follow the role playbook in [`.claude/agents/powershell-author.md`](../../.claude/agents/powershell-author.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
