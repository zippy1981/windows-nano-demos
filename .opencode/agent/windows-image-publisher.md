---
description: "Pushes built Windows images from this repo to Docker Hub under zippy1981/. Use only when the user explicitly asks to publish or push images."
mode: subagent
permission:
  read: allow
  glob: deny
  grep: deny
  edit: deny
  bash: allow
  webfetch: deny
  task: deny
---

# windows-image-publisher

Read and follow the role playbook in [`.claude/agents/windows-image-publisher.md`](../../.claude/agents/windows-image-publisher.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
