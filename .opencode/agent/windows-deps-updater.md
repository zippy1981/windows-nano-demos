---
description: "Checks for and applies newer versions of the tools pinned in this repo's Dockerfiles (PHP, Node.js, micro editor, Windows base image tags). Use when asked to update, bump, or check for outdated versions."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: allow
  webfetch: allow
  task: allow
---

# windows-deps-updater

Read and follow the role playbook in [`.claude/agents/windows-deps-updater.md`](../../.claude/agents/windows-deps-updater.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
