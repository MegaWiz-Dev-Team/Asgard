---
name: deployment
description: Use for building and redeploying Asgard services on the K3s cluster. Covers the dry run with its pre-deploy gates, deploying one target with scripts/k3s-deploy.sh, verifying the rollout, and rolling back. Trigger on deploy, redeploy, release, rollout, or rollback requests.
version: "2.1"
author: asgard-team
tags: [devops, deployment, k3s, kubernetes, rollback]
tools: [fenrir_execute]
---

# Deployment

## Overview
Asgard runs on K3s (OrbStack) on the Mac mini. `scripts/k3s-deploy.sh <target>` is the one deploy path. Before any build it runs both gates (`asgard-build-guard.sh`, then `asgard-deploy-check.sh` for the target). It tags every image `<source-sha>-<YYYYmmddHHMMSS>`, never `:latest`, applies the target's manifest with that image, waits for the rollout, and undoes a rollout that does not become ready.

A deploy changes production. Do steps 1 and 2, then stop for a human's approval before step 3.

## Instructions
1. **Build from a clean source.** The shared checkouts under `~/Developer` are switched between branches by other sessions, and the gate stops a build that is behind `origin/main`. For mimir targets (`api`, `dashboard`), build from a worktree: `git -C ~/Developer/Mimir worktree add /tmp/mimir-main origin/main`, then prefix the commands below with `MIMIR_DIR=/tmp/mimir-main`.
2. **Dry run.** `./scripts/k3s-deploy.sh <target> --dry-run` runs the gates and prints the new tag, the image change, and the rollback command, without building or applying anything. A FAIL stops here; fix the cause. FAILs are sqlx migration drift (an applied migration the build does not embed makes mimir-api panic on boot), low disk, and a failing cluster. A WARN also stops it, and covers a build behind `origin/main`, a dirty tree, pending migrations (back up the DB first), and a service with no readinessProbe. Read it, and add `--accept-warn` only when the warning is understood to be safe.
3. **Deploy, with a human's approval.** The same command without `--dry-run`, plus `--accept-warn` only if step 2 justified it. Add `--no-build` to re-apply manifests and restart the running image without rebuilding.
4. **Verify.** The script waits for `rollout status`; then call the readiness path the gate printed. A new pod can return 404 for 3 to 5 seconds after the rollout, so retest before you call it failed.
5. **Roll back** if a problem shows up after a successful rollout: `kubectl -n <namespace> rollout undo deployment/<deploy>`, or the rollback command printed in step 2. Record why.

## Deploy targets
Generated from the `case "$TARGET" in` arms of `scripts/k3s-deploy.sh`; edit the script, then run `skill-check --write`.

<!-- skill-check:begin k3s-deploy-targets -->
`api`, `dashboard`, `portal`, `bifrost`, `tyr`, `all`
<!-- skill-check:end -->

## Quality Bar
- The dry run's gate verdicts and rollback command are in the deploy log
- Any `--accept-warn` names the warning it accepted
- Rollout status and the health check passed after the deploy
- No deploy ran without a human's approval
