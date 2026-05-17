# Decision — O2: Strip leaked credentials from git history

**Status:** ✅ Done (2026-05-17 evening)
**Originally:** Recommended as deferred / nice-to-have
**Override:** Operator (solo developer) chose to execute it because the residual coordination cost was near zero

## What O2 was

Use `git filter-repo` to remove the rotated-but-leaked credentials from the git history of commit `9651362` (and the four follow-on commits that quoted them in postmortem / decision docs), then force-push the rewritten branch.

The leaked literal values had been in `9651362` plus four subsequent commits that referenced them as evidence in postmortem text.

## Why the original recommendation was "deferred"

The original analysis (in earlier revisions of this doc) noted four reasons not to do it:

1. The leaked values were already dead — O1a/O1b had rotated both.
2. Force-push is destructive in a team context — breaks every local clone.
3. The educational signal in the postmortem cites the exact commit.
4. No external attack value — repo is private, cluster is behind Tailscale.

## Why we did it anyway

The operator confirmed they are working solo on this repo, so:

- No teammates to coordinate with — the main downside of force-push evaporates.
- One open PR (#64) FROM this branch: GitHub auto-updates it; mild noise but no breakage.
- Workflows are disabled — no CI race.
- Other clones on this machine (`_Archive/Asgard`, `actions-runner/_work/Asgard`) are either archived or unused.

Given that, the hygiene benefit (no leaked literal anywhere in upstream history) is worth taking, even though defense-in-depth is already covered by the rotation.

## What was done

1. Mirror backup at `/tmp/Asgard-mirror-backup-20260517-181034.git` (preserves the pre-scrub state in case rollback is ever needed).
2. Fresh clone at `/tmp/Asgard-scrub` to bypass the "already ran" marker left from a previous filter-repo invocation in the main checkout.
3. `git filter-repo --replace-text /tmp/asgard-scrub.txt` against the fresh clone.
4. Verified the two literal passwords appear zero times anywhere in `git log --all -p` of the rewritten clone.
5. `git push --force origin docs/sprint-52-plan-adr-008` — accepted, ref moved `07db7e7 → e7b1a15`.
6. `git push --force origin main` — rejected by branch protection (expected; main never had the leak).
7. Main checkout at `/Users/mimir/Developer/Asgard`: fetched, hard-reset, dropped the stale stash entry that held the pre-scrub state, expired reflog, `git gc --prune=now --aggressive`. Local repo now reports zero hits for both literals.
8. GitHub code search verifies the literals don't appear in the upstream repo.

## Residual cleanup the operator should still do

- `rm -rf /tmp/Asgard-scrub` once satisfied with the result.
- `rm -rf /tmp/Asgard-mirror-backup-20260517-181034.git` after a few days of confidence.
- Inspect `/Users/mimir/Developer/actions-runner/_work/Asgard` — if anything's still cached there it contains the pre-scrub literals.
- `/Users/mimir/Developer/_Archive/Asgard` — same; either prune or accept it as a forensic archive.
- Any other devices with the repo cloned: `git fetch && git reset --hard origin/docs/sprint-52-plan-adr-008`.

## What remains visible

The postmortem still narrates Sonnet 4.6's mistake — the *story* of the leak is intact. What changed is that the literal credential values are now replaced with `REDACTED-MARIADB-PW` / `REDACTED-NEO4J-PW` throughout history. A reader can still see "Sonnet committed real credentials to git", they just can't read the credentials themselves.

## Ready-to-run command (for next time, after the next leak)

```bash
# 1. Stop the bleeding first: rotate the credential. Without rotation,
#    scrubbing only reduces convenience for an attacker, not their access.

# 2. Mirror backup before destroying anything
git clone --mirror . /tmp/repo-mirror-backup-$(date +%Y%m%d-%H%M%S).git

# 3. Run filter-repo in a fresh clone (avoids the "already ran" marker)
git clone <remote> /tmp/repo-scrub
cd /tmp/repo-scrub

cat > /tmp/scrub.txt <<'EOF'
<leaked-literal-1>==>REDACTED-1
<leaked-literal-2>==>REDACTED-2
EOF
git filter-repo --replace-text /tmp/scrub.txt

# 4. Verify
git log --all -p -S '<leaked-literal-1>' | grep -c '<leaked-literal-1>'  # expect 0

# 5. Push
git remote add origin <remote>
git push --force origin <branch>

# 6. Sync the live working checkout
cd <live-checkout>
git stash drop  # if any stash holds the pre-scrub state
git fetch && git reset --hard origin/<branch>
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 7. Confirm GitHub side: gh search code --repo <org>/<repo> '<leaked-literal-1>'
```
