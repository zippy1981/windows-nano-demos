# Runner fleet under Docker Compose

## Goal

Replace the five hand-started runner containers with one Compose project that runs them on a dedicated network beside the artifact cache. Add a script that drains and stops the current runners, and a workflow that tests the Compose files. Then cut over by hand. See [ADR 0015](../docs/adr/0015-runner-fleet-and-artifact-cache-run-under-docker-compose.md).

## Context

- Today: containers `DEARING-HP-Z-nano` … `-nano5`, image `windows-nano-gh-runner:2022`, process isolation, the docker pipe mounted, `--restart unless-stopped`, default `nat` network, registered by `run-runner.ps1`.
- The artifact cache (ADR 0014) merged in #59. On the default `nat` network its IP changes on every restart (#59 found this in its smoke test).
- Checked on the host with plain `docker`: a nat network with `--subnet` and a container `--ip` keeps that IP across `docker restart`. Container names resolve through the network's DNS. The runner image, on that network, process-isolated with the pipe mounted, reaches the daemon, the cache (by IP and by alias) and `api.github.com`.
- Neither the host nor the runner image has Docker Compose.

## Decisions

1. Everything lives in `ci/runner-fleet/`:
   - `compose.yaml`, the fleet
   - `compose.ci.yaml`, the CI test overrides
   - `Install-Compose.ps1`, the pinned Compose binary
   - `Start-RunnerFleet.ps1`, `Stop-ActionRunners.ps1` and `test-compose.ps1`
   - `README.md`
2. Network `windows-nano-ci`: nat, `172.31.250.0/24`. The cache is at `172.31.250.10` with alias `artifact-cache`. Everything can be changed through environment variables, so CI uses `172.31.251.0/24` and its own project name.
3. Runners keep today's registration names, through `RUNNER_NAME`. Containers are named by Compose (`windows-nano-ci-runner1-1` …), so they never clash with the old containers.
4. Runners start after the cache is healthy (`depends_on: condition: service_healthy`, with a `curl.exe` healthcheck).
5. `Stop-ActionRunners.ps1`:
   - selects running containers of `windows-nano-gh-runner` images, or containers whose name matches `-NamePattern`, and skips Compose-managed ones unless `-IncludeFleet`;
   - for each, waits until GitHub reports it idle, then runs `docker stop`;
   - leaves the containers in place for rollback, unless `-Remove`;
   - supports `-WhatIf`.
6. `Start-RunnerFleet.ps1`:
   - refuses to start while old runner containers with the same registration names are running;
   - creates the cache folders;
   - fetches a registration token with `gh`;
   - runs `compose up -d --wait`.
7. The `Compose files` workflow runs on the self-hosted runners with the fork guard, a 30-minute timeout, and one global concurrency group. The convention tests get `DIRECT_DOCKER_WORKFLOWS`, the single exception to ADR 0009's rule, and recognise `test-compose.ps1` as a docker step.

## Plan

- [x] **planning**: ADR 0015 and this plan.
- [x] **cicd-engineer**: `compose.yaml` and `compose.ci.yaml`. Accept: the pytest convention tests over the parsed files pass. `compose config` runs in the workflow.
- [x] **powershell-author**: `Install-Compose.ps1`, `Start-RunnerFleet.ps1`, `Stop-ActionRunners.ps1` and `test-compose.ps1`. Accept: PSScriptAnalyzer is clean, and `Stop-ActionRunners.ps1` drains and stops dummy containers (`-NamePattern claude-*`) with and without `-WhatIf`.
- [x] **workflow-author**: `.github/workflows/compose.yml`. Accept: the convention tests pass.
- [x] **python-author**: `tests/test_compose.py`, plus the convention changes. Accept: `uv run pre-commit run --all-files` passes.
- [ ] **cicd-engineer**: the `Compose files` workflow passes on its PR. It needs the Compose binary to run on the host: see Risks.
- [ ] **Owner (manual cutover)**: `Stop-ActionRunners.ps1`, then `Start-RunnerFleet.ps1`, then check that the five runners are online in GitHub and that a workflow run passes. Rollback: stop the fleet and run `run-runner.ps1` for each name.

## Risks

- **The cutover stops every runner.** Mitigation: `Stop-ActionRunners.ps1` waits for running jobs, and the cutover runs on the host, not in a job. It can't run in a job, because a job would stop its own runner.
- **The Compose binary is a new executable on the host and runners.** It is pinned by version and SHA-256 and checked before use. The first run needs the owner's approval.
- **Windows nat networks.** Their subnets can collide with VPN or Hyper-V switch ranges. Mitigation: everything is configurable, and `test-compose.ps1` uses a different subnet from the fleet.
- **Creating nat networks may disturb running containers.** The first image refresh after #59 failed its smoke test with `curl: (28) Failed to connect` to the cache, while nat networks were being created on the host. The rerun passed, and the cause isn't proven. Mitigation: the Compose test creates one network per run and runs one at a time. If smoke tests fail during Compose runs, give the Compose workflow its own time slot.
- **`--replace` takes over the old registrations.** Rollback needs re-registration (ADR 0015).
- **Builds don't use the cache yet.** Follow-up: wire `--network` and `CACHE_IP` into `build-windows-image.yml`, with the Dockerfile pattern in the artifact cache README.
