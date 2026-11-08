---
description: "Read-only auditor that checks this repo for governance gaps (agents without models or with over-broad tools, images missing workflows, matrix legs, READMEs, or tests, plans without ADRs, ADRs not reflected in code, workflows without fork guards, unpinned versions, missing docs) and returns a ranked gap report. Use before a release, after a large change lands, or when asked what is missing."
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

# governance

Read and follow the role playbook in [`.claude/agents/governance.md`](../../.claude/agents/governance.md). It is the source of truth for this agent. `AGENTS.md` explains how its Claude tool names map to the OpenCode tools allowed here.
