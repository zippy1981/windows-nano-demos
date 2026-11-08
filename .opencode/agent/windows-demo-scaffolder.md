---
description: "Creates a new Windows nanoserver container demo folder following this repo's conventions (Dockerfile with WINDOWS_VERSION arg, build.cmd, README, system32 staging). Use when asked to add a new container or demo, such as Python, Go, .NET, or Ruby on nanoserver."
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

# windows-demo-scaffolder

Read and follow the role playbook in [`.claude/agents/windows-demo-scaffolder.md`](../../.claude/agents/windows-demo-scaffolder.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
