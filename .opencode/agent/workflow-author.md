---
description: "Writes and edits GitHub Actions workflow YAML in .github/workflows/ following this repo's conventions (per-image workflow, fail-fast false matrix over Windows 2019/2022/2025, self-hosted Windows docker runners, fork guard), and validates it with actionlint. Use when adding a workflow for an image or changing triggers, jobs, or steps."
mode: subagent
permission:
  read: allow
  glob: allow
  grep: allow
  edit: allow
  bash: allow
  webfetch: deny
  task: deny
---

# workflow-author

Read and follow the role playbook in [`.claude/agents/workflow-author.md`](../../.claude/agents/workflow-author.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
