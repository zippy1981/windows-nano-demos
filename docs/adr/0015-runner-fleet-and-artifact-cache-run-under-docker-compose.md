# 0015. The runner fleet and the artifact cache run under Docker Compose

- Status: Proposed
- Date: 2026-11-06
- Related: [0003](0003-self-hosted-nanoserver-runners-using-host-docker-daemon-via-named-pipe.md), [0009](0009-all-image-builds-use-one-reusable-workflow.md), [0011](0011-repository-conventions-are-enforced-by-tests-in-ci.md), [0014](0014-artifact-cache-with-caddy-on-ltsc2025.md), [plan](../../plans/runner-fleet-compose.md)

## Context

The five self-hosted runners are separate `docker run` containers started by hand with `run-runner.ps1`, on the default `nat` network. The artifact cache (ADR 0014) is meant to run beside them, but on the default network:

- a container gets a new IP address on every restart, as the cache smoke test found;
- nothing records how the runners and the cache fit together, or starts them in the right order.

## Decision

- **One Compose project**, `ci/runner-fleet/compose.yaml`, describes the cache and the five runners. `Start-RunnerFleet.ps1` starts it. `Stop-ActionRunners.ps1` drains and stops the old hand-started runners before the cutover.
- **A dedicated nat network with a fixed subnet** (`172.31.250.0/24` by default). The cache has a fixed address (`172.31.250.10`) and the network alias `artifact-cache`, so the address survives restarts and container replacement. Runners get `ARTIFACT_CACHE_IP` and `ARTIFACT_CACHE_NETWORK` in their environment, for builds to use later.
- **Runners keep their names** (`<COMPUTERNAME>-nano`, `-nano2` … `-nano5`) and register with `--replace`, so GitHub shows the same five runners. Each container's name comes from Compose, so the old containers can stay, stopped, during the cutover.
- **Compose is a pinned standalone binary** (`docker-compose-windows-x86_64.exe`, version and SHA-256 in `Install-Compose.ps1`). Neither the host nor the runner image has the Compose plugin, and pinning keeps CI and the host on the same version.
- **A `Compose files` workflow tests the Compose files** on the self-hosted runners. It validates them, starts the cache and one runner, with its entrypoint replaced by a connectivity check, on a separate subnet under a throwaway project name, then removes everything. This is the one workflow other than the reusable build workflow allowed to run docker directly. `tests/repo_conventions.py` lists it in `DIRECT_DOCKER_WORKFLOWS`, so ADR 0009's rule stays enforced for every other workflow.

## Consequences

- The cutover replaces the runner registrations. Rolling back to the old containers means running `run-runner.ps1` again for each name, because `--replace` invalidates the old registrations.
- The fleet's subnet must not overlap any other network on the host. It is configurable through `FLEET_SUBNET`, `FLEET_GATEWAY` and `CACHE_IP`.
- The Compose test runs only one job at a time (a workflow-wide concurrency group), because its subnet is fixed.
- The registration token is in the runner containers' environment, as it is today. It expires an hour after `Start-RunnerFleet.ps1` fetches it, and is needed only for the first registration.
- Image builds still don't use the cache. Passing `--network` and `CACHE_IP` through `build-windows-image.yml` is a follow-up, and now has a stable address to point at.

## Alternatives considered

- **Keep `docker run` scripts and add a fixed IP by hand.** That works, but it spreads the topology over several scripts, and nothing in CI can check it.
- **Use the `docker compose` plugin.** It isn't installed on the host or in the runner image. A pinned standalone binary needs no install step and behaves the same.
- **Ephemeral, just-in-time runners.** They give cleaner isolation per job, but need a GitHub App or PAT to mint JIT configs, and a supervisor to replace runners. That's a larger change than this cutover.
- **New runner names for the fleet.** They would make rollback a plain `docker start`, but they leave five offline runners in GitHub until they expire, and they would change every runner name in job logs.
