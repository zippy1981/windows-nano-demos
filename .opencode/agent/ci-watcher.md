---
description: "Waits for a GitHub Actions run or a pull request's checks in this repo to finish, then reports only the outcome and, for failures, the failing step and error lines. Use instead of polling CI yourself, for example after a push or merge, or while waiting to merge a PR."
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

# ci-watcher

Read and follow the role playbook in [`.claude/agents/ci-watcher.md`](../../.claude/agents/ci-watcher.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
