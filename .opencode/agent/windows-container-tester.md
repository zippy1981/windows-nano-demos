---
description: "Smoke-tests built Windows container images in this repo by running each image's smoke-test.ps1, plus extra tool checks when asked. Use after a build or when asked whether an image works."
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

# windows-container-tester

Read and follow the role playbook in [`.claude/agents/windows-container-tester.md`](../../.claude/agents/windows-container-tester.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
