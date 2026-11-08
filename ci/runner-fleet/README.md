# Runner fleet

The five self-hosted GitHub Actions runners and the [artifact cache](../../nano-server/nano-server-artifact-cache/README.md), as one Docker Compose project on their own nat network ([ADR 0015](../../docs/adr/0015-runner-fleet-and-artifact-cache-run-under-docker-compose.md), [plan](../../plans/runner-fleet-compose.md)).

| File | What it does |
| --- | --- |
| `compose.yaml` | The fleet: `artifact-cache` and `runner1` … `runner5` on network `windows-nano-ci` |
| `compose.ci.yaml` | Overrides for the CI test: throwaway volumes, and a connectivity check instead of registering `runner1` |
| `Install-Compose.ps1` | Downloads the pinned `docker-compose.exe` and checks its SHA-256. Neither the host nor the runner image has Compose. |
| `Stop-ActionRunners.ps1` | Waits for each hand-started runner to go idle, then stops its container |
| `Start-RunnerFleet.ps1` | Gets a registration token and runs `compose up --wait` |
| `test-compose.ps1` | The `Compose files` workflow's test |

## Network

| Setting | Default | Variable |
| --- | --- | --- |
| Network | `windows-nano-ci`, nat | `FLEET_NETWORK` |
| Subnet | `172.31.250.0/24`, gateway `.1` | `FLEET_SUBNET`, `FLEET_GATEWAY` |
| Cache | `172.31.250.10`, alias `artifact-cache` | `CACHE_IP` |

The cache's address is fixed, so it survives restarts. On the default `nat` network, a restarted container gets a new IP. Runners get `ARTIFACT_CACHE_IP` and `ARTIFACT_CACHE_NETWORK` in their environment, which jobs inherit. Builds don't use them yet: that's a follow-up, using the Dockerfile pattern in the cache README.

The CI test uses `172.31.251.0/24` and a `ci-compose-<run id>` project, so it never touches the fleet. Make sure neither subnet overlaps a VPN or Hyper-V switch on the host.

## Runners

- Same image, process isolation and docker pipe as before (`windows-nano-gh-runner:2022` by default, `-RunnerImage` to change).
- Registration names stay `<COMPUTERNAME>-nano` and `-nano2` … `-nano5`. The runners register with `--replace`, so GitHub keeps the same five.
- Compose names the containers `windows-nano-ci-runner1-1` and so on, so they never clash with the old `DEARING-HP-Z-nano*` containers.
- Each runner starts only after the cache is healthy. A runner that is recreated, for example after an image change, registers again with the token `Start-RunnerFleet.ps1` supplies. Run that script, not raw `compose up`.

## Runners for other repositories

A runner on a personal account serves exactly one repository, so the fleet's five runners only take `windows-nano-demos` jobs. To give another repository its own runners on the same host, network and cache, start them from `compose.runners.yaml` with `Start-RepoRunners.ps1`:

```powershell
./ci/runner-fleet/Start-RepoRunners.ps1 -Repo zippy1981/windows-nano-baseimages   # 2 runners: <COMPUTERNAME>-base1, -base2
```

- Each repository gets its own compose project, named after the repository (`windows-nano-baseimages`), so `compose down` on one never touches another or the fleet.
- The runners join the fleet's `windows-nano-ci` network and get the same `ARTIFACT_CACHE_IP` and `ARTIFACT_CACHE_NETWORK`. The fleet must be running first; the script checks for the network.
- They don't wait for the cache's health, because the cache belongs to another project. `restart: unless-stopped` brings them back after a reboot either way.
- `-Count` (1–5, default 2), `-NamePrefix`, `-RunnerImage` and `-WhatIf` work as in `Start-RunnerFleet.ps1`.
- To remove them for good: `& (./ci/runner-fleet/Install-Compose.ps1) -p windows-nano-baseimages down`. Then remove the runners under the repository's **Settings → Actions → Runners**. To stop them for a while, see the next section.

## Fewer runners for a while

`Set-RunnerCount.ps1` keeps `runner1` to `runner<Count>` running in every runner project (the fleet and each repository's runners) and stops the rest. It never touches the artifact cache.

```powershell
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 1 -WhatIf   # see what it would do
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 1           # one runner per repository
./ci/runner-fleet/Set-RunnerCount.ps1 -Count 5           # back to full size
```

- **Stopping waits for jobs.** Runners above `-Count` are stopped through `Stop-ActionRunners.ps1 -Container`, which waits until GitHub reports each runner idle in the repository it serves. `-DrainMinutes` (default 60) and `-Force` work the same way as there.
- **Starting needs no token.** Stopped runners are still registered with GitHub. They show as offline while stopped, and `docker start` brings them back.
- **Stopped stays stopped,** through Docker and host restarts (`restart: unless-stopped`). The exception is running `Start-RunnerFleet.ps1` or `Start-RepoRunners.ps1`, which starts every runner it manages.
- **`-Project windows-nano-ci`** scales only the fleet, and **`-Project windows-nano-baseimages`** only that repository's runners.
- **It can't create runners.** A runner the project never created needs a registration token. The script says which start script to run with which `-Count`.

## Cutover

Run these on the host, in an elevated PowerShell 7 that has `gh` logged in. Never run them from a workflow: a job would stop its own runner.

1. **Have the images.** `windows-nano-gh-runner:2022` is already on the host. Build the cache:

   ```cmd
   nano-server\nano-server-artifact-cache\build.cmd
   ```

   That tags `windows-nano-artifact-cache:2025`. Once Docker Hub has it, `docker pull zippy1981/windows-nano-artifact-cache:2025` and `-CacheImage` work too.
2. **Check what will stop:**

   ```pwsh
   ./ci/runner-fleet/Stop-ActionRunners.ps1 -WhatIf
   ```

3. **Drain and stop the old runners.** Each container is stopped once GitHub reports its runner idle. The default wait is 60 minutes, `-DrainMinutes` changes it, and `-Force` stops busy ones. The containers are kept for rollback.

   ```pwsh
   ./ci/runner-fleet/Stop-ActionRunners.ps1
   ```

4. **Start the fleet:**

   ```pwsh
   ./ci/runner-fleet/Start-RunnerFleet.ps1
   ```

5. **Check it:**
   - all five runners show online in Settings → Actions → Runners;
   - `docker ps` shows `windows-nano-ci-*` and the cache `(healthy)`;
   - re-run any workflow, and it passes.

### Rollback

Stop the fleet, and register the old containers again:

```pwsh
& (./ci/runner-fleet/Install-Compose.ps1) -f ./ci/runner-fleet/compose.yaml down
1..5 | ForEach-Object { $n = if ($_ -eq 1) { "$env:COMPUTERNAME-nano" } else { "$env:COMPUTERNAME-nano$_" }; ./nano-server/nano-server-gh-runner/run-runner.ps1 -Name $n -Image windows-nano-gh-runner:2022 }
```

A plain `docker start` of the old containers isn't enough. The fleet's `--replace` registration invalidated their credentials.

## Testing

The `Compose files` workflow (`.github/workflows/compose.yml`) runs `test-compose.ps1` on every change here or to the cache image. It does this:

1. Validates `compose.yaml`, alone and with `compose.ci.yaml`, and `compose.runners.yaml`.
2. Builds the cache image.
3. Downloads an artifact through the cache twice (MISS, then HIT), restarts the cache, and checks that its address didn't change and the artifact is still a HIT.
4. Runs `runner1`'s connectivity check (docker pipe, cache by address and by name, GitHub).
5. Removes everything.

`tests/test_compose.py` checks the files' safety rules without docker: process isolation and the pipe, no bind mounts on runners, the token taken from the environment, the fixed cache address inside the subnet, and the CI overrides.
