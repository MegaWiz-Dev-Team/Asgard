---
name: deployment
description: Use for building and redeploying Asgard services on the K3s cluster. Covers the pre-deploy gates, deploying one target with scripts/k3s-deploy.sh, verifying the rollout, and rolling back. Trigger on deploy, redeploy, release, rollout, or rollback requests.
version: "2.0"
author: asgard-team
tags: [devops, deployment, k3s, kubernetes, rollback]
tools: [fenrir_execute]
---

# Deployment

## Overview
Asgard runs on K3s (OrbStack) on the Mac mini. `scripts/k3s-deploy.sh <target>` is the one deploy path: it builds the image locally and applies the target's manifests. This skill wraps it with the two gates that came out of real regressions, and makes the rollback ready before the deploy starts.

A deploy changes production. Prepare everything, then stop for a human's approval before step 3.

## Instructions
1. **Run the gates** from `scripts/`. Do not continue on a FAIL.
   - `./asgard-deploy-check.sh <deploy>` exits 0 for OK, 1 for WARN (read it, then decide), and 2 for FAIL (do not deploy). It catches a build branch behind `origin/main`, a dirty tree, and sqlx migration drift: an applied migration that the build does not embed makes mimir-api panic on boot. Pending migrations mean you back up the DB first. Its defaults point at mimir-api; for another service set `REPO` to that service's checkout and `MIG_DIR=` (empty) unless it embeds sqlx migrations.
   - `./asgard-build-guard.sh` checks host disk, memory, and cluster health.
2. **Make the rollback ready.** Copy the current image and the rollback command that `asgard-deploy-check.sh` prints into the deploy log.
3. **Deploy, with a human's approval.** From the repo root, run `./scripts/k3s-deploy.sh <target>`, one of the targets listed below. Add `--no-build` to re-apply manifests and restart without rebuilding.
4. **Verify.** `kubectl -n asgard rollout status deploy/<deploy> --timeout=120s`, then call the readiness path that `asgard-deploy-check.sh` printed. A new pod can return 404 for 3 to 5 seconds after the rollout, so retest before you call it failed.
5. **Roll back** with the step 2 command if the rollout or the health check fails, and record why.

## Deploy targets
Generated from the `case "$TARGET" in` arms of `scripts/k3s-deploy.sh`; edit the script, then run `skill-check --write`.

<!-- skill-check:begin k3s-deploy-targets -->
`api`, `dashboard`, `portal`, `bifrost`, `tyr`, `all`
<!-- skill-check:end -->

## Quality Bar
- Both gates ran, and their verdicts are in the deploy log
- A rollback command was recorded before the deploy
- Rollout status and the health check passed after the deploy
- No deploy ran without a human's approval
