# 0019. A runner container can run several runners

- Status: Proposed
- Date: 2026-11-11
- Related: [0003](0003-self-hosted-nanoserver-runners-using-host-docker-daemon-via-named-pipe.md), [0015](0015-runner-fleet-and-artifact-cache-run-under-docker-compose.md), [`nano-server-gh-runner/`](../../nano-server/nano-server-gh-runner/README.md), [`ci/runner-fleet/`](../../ci/runner-fleet/README.md)

## Context

The fleet runs one runner in each container, and the Compose files list five containers by hand. Two things were fixed that should be settings:

- **How many jobs the host takes at once.** A GitHub Actions runner takes exactly one job at a time. There is no setting that makes one runner take several. The only way to run more jobs is more runners, and until now that meant more containers, up to the five the Compose files list.
- **How a runner registers.** The entrypoint passed only the name and the labels to `config.cmd`. The runner group, the work folder, ephemeral registration and self-update were not reachable.

Measured on the fleet's host on 2026-11-11:

- An idle runner container uses 40 to 48 MB of memory.
- The runner's folder is 246 MB.
- A runner folder made of junctions to `C:\actions-runner\bin` and `externals` keeps its own root. Its `_diag` lands in the new folder, not the shared one.

## Decision

- **`RUNNER_COUNT` sets the runners in a container,** from 1 to 16. The default, 1, is unchanged: `RUNNER_NAME`, in `C:\actions-runner`. With more, the first registers as `RUNNER_NAME` and runner *n* as `RUNNER_NAME-<n>`. Each has a folder, `C:\actions-runner-<n>`, with its own registration, `_work` and `_diag`, and with `bin` and `externals` as junctions to `C:\actions-runner`, which then runs nothing itself.
- **The entrypoint supervises the runners.** With more than one, it starts each as a child process. One that exits is started again, and the others keep their jobs.
- **The other registration options are environment variables:** `RUNNER_GROUP`, `RUNNER_WORKDIR`, `RUNNER_EPHEMERAL`, `RUNNER_DISABLE_UPDATE` and `RUNNER_NO_DEFAULT_LABELS`.
- **The fleet passes it through.** `Start-RunnerFleet.ps1` and `Start-RepoRunners.ps1` take `-RunnersPerContainer`, `-Labels` and `-DisableUpdate`. The Compose files read `RUNNERS_PER_CONTAINER`, `RUNNER_LABELS` and `RUNNER_DISABLE_UPDATE`. The defaults give the fleet that runs today.
- **`Stop-ActionRunners.ps1` treats a container as busy while any of its runners is busy,** so draining still never cuts off a job.
- **`start.ps1 -Mode Plan` and `-Mode Prepare`** print the runners and options without registering, so the image's smoke test checks all of this without a token.

## Consequences

- The fleet's size has two settings: containers (`-Count`) and runners in each (`-RunnersPerContainer`). The five-container limit no longer limits the number of jobs.
- Jobs in one container share its filesystem, user profile and temp folder. The publish step already keeps its docker login in a throwaway folder. A job that writes to a fixed path outside its workspace can now collide with a job beside it.
- Stopping or recreating a container stops every runner in it. A container with several runners takes longer to drain.
- The memory saved is small, about 45 MB for each container avoided. The gain is configuration, not capacity. The host's cores and memory still bound how many builds are worth running at once.
- Each runner updates itself on its own. The runner's Windows updater (`update.cmd.template`) expects `bin` to be a junction after the first update: it downloads the new version into the runner's own folder and re-points the junction. So the shared `C:\actions-runner` never changes under a running job, and a container with *n* runners downloads a runner release *n* times. `RUNNER_DISABLE_UPDATE` avoids the downloads, at the cost of rebuilding the image for each runner release.
- Lowering either number leaves registrations behind in GitHub, offline, until someone removes them.

## Alternatives considered

- **One runner that takes several jobs.** The runner has no such mode.
- **More containers, from a Compose `scale` or `deploy.replicas`.** It keeps one runner in each container, which isolates jobs better. But replicas share one environment, so every replica would register under a name derived from its own host name, and `Set-RunnerCount.ps1` and the cutover's fixed names depend on the names in the Compose files. It is still open as a later step.
- **Copy the runner folder for each runner.** It is simpler than junctions, and each runner could update on its own. It costs 246 MB and several seconds for each runner at every container creation.
- **Ephemeral runners from just-in-time configs.** They give each job a clean runner. They need a supervisor on the host that mints a config and starts a container for every job (ADR 0003, ADR 0015). `RUNNER_EPHEMERAL` is the piece of that the image can provide now.
