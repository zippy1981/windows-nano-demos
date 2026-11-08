---
description: "Writes and edits Windows Dockerfiles (nanoserver, with servercore build stages where needed) and their build.cmd scripts following this repo's conventions. Use to change an existing image's Dockerfile, add a build stage or tool, or write a Dockerfile for a folder that already exists. For a brand-new demo folder, use windows-demo-scaffolder instead."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: deny
  webfetch: allow
  task: allow
---

# container-author

Read and follow the role playbook in [`.claude/agents/container-author.md`](../../.claude/agents/container-author.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
