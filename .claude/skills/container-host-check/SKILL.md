---
name: container-host-check
description: Check this Windows host's container setup in one read-only command - OS build, Docker engine mode and isolation, Hyper-V and Containers features, which LTSC bases the host can run, free disk, host files build.cmd copies, and the download hosts - as one pass, warn or fail row each with its fix. Use when builds or runs fail for environmental reasons, before a first build on a new machine, and in windows-host-doctor.
---

# Container host check

```pwsh
./scripts/Test-ContainerHost.ps1                # table
./scripts/Test-ContainerHost.ps1 -Json          # for scripting
./scripts/Test-ContainerHost.ps1 -SkipNetwork   # offline, or to save time
```

It changes nothing. Each row has a check, `pass`, `warn` or `fail`, the evidence, and the fix. It exits 1 when any row fails. Report only the rows that aren't `pass`, with their fixes, and mark the ones that need admin rights or a reboot.

- **Features need elevation to read.** Without it, the two feature rows are `warn` with "requires elevation". That isn't a failure. Ask the user to run the check from an elevated shell only if the features matter to the problem.
- **Base images:** with Hyper-V isolation, which is the default on Windows 11, any LTSC base no newer than the host runs. With process isolation, only the host's own build runs, and the others need `--isolation=hyperv`.
- **Disk:** it fails below 20 GB free on the Docker root drive (`-MinimumFreeGB`) and warns below twice that. Free space with the `safe-docker-cleanup` skill. Never prune: the daemon is shared with the runners.
- **Network:** this checks from the host. If the host passes but a build can't download, the problem is DNS or a proxy inside the container.

Never apply a fix that changes the host, such as switching the engine, enabling features, or changing firewall or DNS settings, without asking first.
