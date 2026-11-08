---
description: "Builds the Windows (nanoserver / servercore) container images in this repo. Use when asked to build, rebuild, or tag any image here, for one or all Windows versions (ltsc2019, ltsc2022, ltsc2025)."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: deny
  bash: allow
  webfetch: deny
  task: deny
---

# windows-container-builder

Read and follow the role playbook in [`.claude/agents/windows-container-builder.md`](../../.claude/agents/windows-container-builder.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
