# 0018. Publishing nanoserver-base dispatches the image refresh

- Status: Proposed
- Date: 2026-11-10
- Related: [0004](0004-rebuild-all-images-on-base-image-digest-change.md), [0006](0006-publish-to-docker-hub-only-from-main-via-scheduled-workflow.md), [0017](0017-nano-server-images-build-on-zippy1981-nanoserver-base.md), [#77](https://github.com/zippy1981/windows-nano-demos/issues/77), [#71](https://github.com/zippy1981/windows-nano-demos/issues/71)

## Context

Since ADR 0017, the Nano Server images build on `zippy1981/nanoserver-base`, and `image-refresh.yml` compares its Docker Hub digest with the label on each published image twice a day (06:00 and 18:00 UTC). A base change therefore takes two hops: Microsoft to nanoserver-base (its weekly run, or a push to its `main`), then nanoserver-base to these images (the next poll here). The second hop adds up to 12 hours. #77 asked whether a publish should trigger the refresh instead, what token that needs, and how it fits with ADR 0004 and the timer.

## Decision

- **Both, not either.** `image-refresh.yml` keeps its twice-daily schedule and also runs on `repository_dispatch` of type `nanoserver-base-published`.
- **windows-nano-baseimages sends the dispatch** from `nanoserver-base.yml`, in a job that runs after every Windows version has been published from `main`. The job is skipped when its token secret isn't set, so the sender can merge before the token exists.
- **The dispatch carries no instructions.** It only starts a run. `scripts/refresh_matrix.py` still decides what to rebuild by comparing digests and revisions (ADR 0004), so a dispatch for a base that didn't change builds nothing.
- **The token** is a fine-grained personal access token, scoped to `zippy1981/windows-nano-demos` only, with the **Contents: Read and write** permission (the minimum that `POST /repos/{owner}/{repo}/dispatches` accepts). It is stored as `DEMOS_DISPATCH_TOKEN` in windows-nano-baseimages' `Docker Hub zippy1981` environment, next to the Docker Hub secrets, so only publishing runs from `main` can read it. It expires, and it is renewed by hand.

## Consequences

- A new nanoserver-base reaches the Nano Server images minutes after it is published, instead of within 12 hours.
- **The timer and the dispatch don't conflict.** The `image-refresh` concurrency group queues runs rather than cancelling them, and detection is stateless. Whichever run comes second finds the labels already current and builds nothing.
- If the token expires or the dispatch fails, nothing is lost: the next scheduled poll finds the same change. A failed dispatch fails only the sender's notify job, not its publish.
- Contents write is broader than a dispatch needs, because GitHub has no narrower permission for it. Scoping the token to this one repository and keeping it in the publishing environment limits the risk.

## Alternatives considered

- **Dispatch only, and drop the timer:** a missed dispatch (expired token, outage) would leave images unpatched until the next push. The timer also catches MCR updates for the Server Core image, which has no sender.
- **Timer only (the state before this record):** no token to manage, but up to 12 hours late.
- **A `workflow_dispatch` call from the sender instead of `repository_dispatch`:** needs Actions write as well, and couples the sender to this workflow's file name and inputs.
- **A GitHub App instead of a personal access token:** no expiry to renew and narrower ownership, but more setup than one dispatch justifies for a single-owner pair of repositories. Worth revisiting if more repositories send dispatches.
