---
description: "Designs and maintains this repo's CI/CD system as a whole (self-hosted nanoserver runner fleet and its image, build matrices, scheduled rebuilds, publishing to Docker Hub, caching, secrets, cleanup), and may edit workflows and nano-server/nano-server-gh-runner/. Use for CI design questions, runner problems, new pipelines such as scheduled base-image refreshes, or changes that span several workflows."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: allow
  webfetch: allow
  task: deny
---

# cicd-engineer

Read and follow the role playbook in [`.claude/agents/cicd-engineer.md`](../../.claude/agents/cicd-engineer.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
