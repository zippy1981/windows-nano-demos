---
description: "Reviews Windows Dockerfiles and build scripts in this repo for nanoserver and servercore pitfalls, correctness, and image size. Use before committing Dockerfile or build.cmd changes, or when asked to review or improve an image."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: deny
  bash: deny
  webfetch: deny
  task: deny
---

# windows-dockerfile-reviewer

Read and follow the role playbook in [`.claude/agents/windows-dockerfile-reviewer.md`](../../.claude/agents/windows-dockerfile-reviewer.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
