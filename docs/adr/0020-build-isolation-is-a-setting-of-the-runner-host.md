# 0020. Build isolation is a setting of the runner host

- Status: Proposed
- Date: 2026-11-11
- Related: [0003](0003-self-hosted-nanoserver-runners-using-host-docker-daemon-via-named-pipe.md), [0008](0008-images-take-windows-version-defaulting-to-2025-built-as-a-matrix.md), [0009](0009-all-image-builds-use-one-reusable-workflow.md), [`build-windows-image.yml`](../../.github/workflows/build-windows-image.yml)

## Context

The runner host is a Windows 11 machine with 8 logical processors. Its docker daemon defaults to Hyper-V isolation, and `build-windows-image.yml` builds with that default. Measured on the host on 2026-11-11, with the runners idle, one run each:

| Measurement | Process isolation | Hyper-V isolation |
| --- | --- | --- |
| Processors a container sees | 8 | 2 |
| SHA-256 hashes in 5 s on 8 threads (`windows-nano-gh-runner:2022`) | 48,003 | 31,791 (66,954 with `--cpu-count 8`) |
| Uncached build of five small `RUN` steps on `nanoserver:ltsc2025` | 53.7 s | 51.6 s |
| Three `docker run --rm` of that image | 14.2 s | 19.6 s |
| The same build on `nanoserver:ltsc2022` | 77.0 s | 125.3 s |
| Three `docker run --rm` of the ltsc2022 image | 29.0 s | 55.9 s |

- **A Hyper-V isolated container gets 2 processors.** `docker run` can raise that with `--cpu-count`. `docker build` has no such option, so every build step runs on 2 processors however idle the host is.
- **The fixed cost of a step is about the same on ltsc2025,** about 10 seconds for each `RUN` either way, so there only builds that compile or compress gain from more processors. On ltsc2022 the process isolated build was faster, but tests were running on the host during the Hyper-V measurement, so that gap needs measuring again in CI.
- **The host runs ltsc2022 and ltsc2025 under process isolation.** The runner containers themselves do. It can't run ltsc2019 that way.

Which Windows versions a host can run under process isolation depends on the host's own Windows build. A different host, or a GitHub-hosted runner, has a different answer.

## Decision

- **The repository variable `WINDOWS_BUILD_ISOLATION` chooses the isolation for each Windows version.** It is a JSON map, for example `{"2022": "process", "2025": "process"}`. `build-windows-image.yml` passes `--isolation` to the image build for the versions the map names.
- **Unset, nothing changes.** A version the map doesn't name builds with the daemon's default, as every version does today.
- **Only `process` and `hyperv` are accepted.** Anything else fails the build step with a message that names the variable.
- **Only the image build takes it.** Smoke tests keep the daemon's default, so they still start the image the way a user's `docker run` would.
- **It is a variable, not a workflow input,** because it describes the host, not the image. No image workflow changes, and a change of host needs no commit.

## Consequences

- Setting the variable is an experiment the `CI speed report` can measure: add a milestone to `ci/speed-milestones.json` on the day it is set.
- Process isolated builds share the host's kernel. A build step runs as a process on the host, with less separation than a Hyper-V container. The jobs already hold the docker pipe, which is administrator access to the host, so this adds no new trust (ADR 0003).
- More processors for each build means more contention when every runner is busy. The fleet's size and this setting need tuning together.
- The built layers are the same either way, and the layer cache is kept: isolation isn't part of what the cache compares.
- A wrong value for a version the host can't run under process isolation fails that version's builds until the variable is fixed.

## Alternatives considered

- **Set the daemon's default isolation to process.** It would also change every `docker run`, and it would break the ltsc2019 builds, which need Hyper-V on this host.
- **A workflow input for each image.** Images don't know what host they build on, and every image workflow would repeat the same map.
- **Detect the host in the build step.** The rules for which versions run under process isolation changed between Windows releases. A wrong guess would fail builds, and a variable is easy to correct.
- **`--cpu-count` for Hyper-V builds.** `docker build` doesn't have it.
