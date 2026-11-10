---
name: governance-scan
description: Run the mechanical half of a governance audit (convention tests, actionlint, outdated pins) and collect only the failures, so the governance agent gets a short list and spends its effort on judgement instead of reading the whole repo. Use before starting the governance agent, before a release, or when asked what is missing.
---

# Governance scan

`governance` runs on opus with no shell, so everything it checks by reading files costs the most expensive tokens. Most of its checklist is enforced by tests. Run those first, from the repo root, and give the agent only what failed:

```bash
uv run pytest -q --tb=line -p no:cacheprovider 2>&1 | tail -40   # conventions
uv run python scripts/actionlint.py                                  # workflow lint (the actionlint skill)
uv run python scripts/check_versions.py --outdated                   # pins behind upstream (the version-check skill)
```

What the tests already cover, so the auditor doesn't re-check it by reading files:

| Area | Tests |
| --- | --- |
| Agent front matter, the agents README table, skills and agents the playbooks name, read-only reviewers | `tests/test_governance.py` |
| OpenCode wrappers match the playbooks | `tests/test_opencode_config.py` |
| ADR index lists every record with its status, unique numbers | `tests/test_governance.py` |
| Every image has a README linked from the root README | `tests/test_governance.py` |
| Fork guards, runner labels, timeouts, pinned third-party actions, `pull_request_target`, secrets, publishing only from `main` | `tests/test_workflows.py` |
| `WINDOWS_VERSION` and `BASE_IMAGE` arguments, the final stage, `build.cmd` defaults | `tests/test_images.py`, `tests/test_image_layout.py` |
| Dockerfile header and build-argument comments | `tests/test_dockerfile_docs.py` |
| Every version pin has an upstream source | `tests/test_check_versions.py` |

Then start the `governance` agent with this in its prompt:

- the failure lines from the three commands, or "all clean"
- this instruction: "The mechanical checks above are done. Don't re-verify them by reading files. Audit what tests can't check: Accepted ADRs the code contradicts, Proposed ADRs whose work has landed, plans whose decisions need an ADR that doesn't exist, ADR numbering gaps, tools broader than an agent's body needs, model choices that don't fit the job, docs that drift from the code, and security judgement on self-hosted jobs and secrets."

A convention that the ADRs state but no test checks is itself a finding for `governance` to report, with `python-author` as the owner of the new test.
