# GitHub Actions runner on Windows nano server

A self-hosted [GitHub Actions runner](https://github.com/actions/runner) in a nano server container, built on [`zippy1981/nanoserver-base`](https://github.com/zippy1981/windows-nano-baseimages/tree/main/images/nanoserver-base)'s `-pwsh` tag (ADR 0017). It has PowerShell 7 from the base (the smoke test requires 7.4 or later), with a `powershell.exe` copy for the runner, plus MinGit and the docker CLI. There is no docker daemon in the image. Jobs build and run containers on the host's daemon through its named pipe.

This repo's workflows run on it with `runs-on: [self-hosted, windows, docker]`.

## Building

```cmd
build.cmd
```

## Running

The host's docker pipe can only be mounted into a process-isolated container, so the image's Windows version has to be compatible with the host. `ltsc2025`, the default, and `ltsc2022` both work on Windows 11 build 26100 and later. `ltsc2022` also works on Windows Server 2022. `ltsc2019` doesn't support process isolation on newer hosts.

`run-runner.ps1` gets a registration token with the `gh` CLI and starts the container:

```pwsh
./run-runner.ps1 -Repo zippy1981/windows-nano-demos
```

The equivalent `docker run` is:

```pwsh
docker run -d --name runner --restart unless-stopped --isolation=process `
    -v '\\.\pipe\docker_engine:\\.\pipe\docker_engine' `
    -e RUNNER_URL=https://github.com/zippy1981/windows-nano-demos `
    -e RUNNER_TOKEN=<registration token> `
    windows-nano-gh-runner:2025
```

Optional environment variables:

| Variable | Default | What it does |
| --- | --- | --- |
| `RUNNER_NAME` | the container's host name | Registration name |
| `RUNNER_LABELS` | `nanoserver,docker` | Extra labels. GitHub adds `self-hosted`, `Windows` and `X64` itself. |
| `RUNNER_COUNT` | `1` | Runners in this container, 1 to 16. See [Several runners in one container](#several-runners-in-one-container). |
| `RUNNER_GROUP` | none | Runner group, for organization runners |
| `RUNNER_WORKDIR` | `_work` | Work folder, relative to each runner's folder |
| `RUNNER_EPHEMERAL` | off | `1`: each runner takes one job, then unregisters. The container exits when all are done, so whatever starts it has to supply a fresh token each time. Don't combine it with `--restart`. |
| `RUNNER_DISABLE_UPDATE` | off | `1`: the runner doesn't update itself. GitHub stops sending jobs to a runner about 30 days after a newer one is released, so rebuild the image before then. |
| `RUNNER_NO_DEFAULT_LABELS` | off | `1`: don't add `self-hosted`, `Windows` and `X64` |

The runner registers on first start. The registration stays in the container, so `docker restart` reuses it without a new token. `docker rm` loses it. Run `run-runner.ps1` again to register a fresh one (`--replace` reuses the same name).

`start.ps1 -Mode Plan` prints the runners and `config.cmd` options the environment asks for, as JSON, without a token and without changing anything.

## Several runners in one container

A GitHub Actions runner takes one job at a time. A container takes several jobs at once by running several runners, with `RUNNER_COUNT`, or `run-runner.ps1 -Count`:

```pwsh
./run-runner.ps1 -Name "$env:COMPUTERNAME-multi" -Count 3
```

- The first runner registers as `RUNNER_NAME`, and the others as `RUNNER_NAME-2`, `RUNNER_NAME-3` and so on. One registration token registers all of them.
- Each runner has its own folder (`C:\actions-runner-1`, `C:\actions-runner-2` …) with its own registration, `_work` and `_diag`. Its `bin` and `externals` are junctions to `C:\actions-runner`, which is 246 MB and then runs nothing itself, so a runner costs no disk space.
- Each runner updates itself on its own. The runner's updater downloads the new version into the runner's folder and points the junction at it, so the shared folder never changes under a running job.
- A runner that exits is started again after a few seconds. The other runners keep their jobs.
- All the runners write to the one container log.

What to weigh up:

- **It saves little memory.** An idle runner container uses about 45 MB. The gain is fewer containers to start, name and watch.
- **The jobs share a container.** They share `C:\`, the user profile and the temp folder, so a job can see and break another job's files. Separate containers keep those apart. Either way, every job shares the host's docker daemon.
- **Stopping the container stops every runner in it.** `Stop-ActionRunners.ps1` waits until all of them are idle.
- **Lowering `RUNNER_COUNT` leaves registrations behind.** Remove the extra runners under the repository's **Settings → Actions → Runners**.

## Security

Access to the docker pipe is equivalent to administrator access on the host. Any workflow that runs on this runner can take over the machine. The workflows in this repo skip pull requests from forks. Keep "Require approval for all outside collaborators" turned on in the repository's Actions settings.

## Limitations

- `actions/setup-*` actions work, because PowerShell is present for their archive extraction.
- Job containers (`container:` in a workflow) and service containers aren't supported on Windows runners. Call `docker` from steps instead.
- The job workspace is inside the runner container, so `docker run -v <workspace>:...` paths don't exist on the host. Bake files into images, or use `docker cp`.
