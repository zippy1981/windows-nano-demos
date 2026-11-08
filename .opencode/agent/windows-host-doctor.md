---
description: "Diagnoses the Windows host's container setup for this repo (Docker engine mode, Hyper-V and containers features, isolation, base image and OS compatibility, disk space, build prerequisites like 7-Zip and the VC++ runtime). Use when builds or runs fail for environmental reasons or before a first build on a new machine."
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

# windows-host-doctor

Read and follow the role playbook in [`.claude/agents/windows-host-doctor.md`](../../.claude/agents/windows-host-doctor.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
