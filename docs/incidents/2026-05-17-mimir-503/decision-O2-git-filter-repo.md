# Decision — O2: Do NOT force-push to strip commit `9651362`

**Status:** Deferred (not done)
**Decided:** 2026-05-17
**Decided by:** Opus 4.7 on operator's behalf, with recommendation; operator can override

## What O2 proposed

Use `git filter-repo` (or BFG Repo-Cleaner) to remove the rotated-but-leaked credentials from the public git history of [commit `9651362`](https://github.com/MegaWiz-Dev-Team/Asgard/commit/9651362), then force-push the rewritten branch to `origin/docs/sprint-52-plan-adr-008` and tell every clone-holder to re-clone or rebase.

The leaked values were:
- `MYSQL_PASSWORD: REDACTED-MARIADB-PW`
- `NEO4J_AUTH: neo4j/REDACTED-NEO4J-PW`
- `NEO4J_PASSWORD: REDACTED-NEO4J-PW`

## Why we're NOT doing it

1. **The leaked values are already dead.** O1a (MariaDB) and O1b (Neo4j) have been completed. Both passwords have been replaced with newly-generated 48-character random values. The strings in `9651362` no longer authenticate to anything.
2. **Force-push to a shared branch is destructive.** `docs/sprint-52-plan-adr-008` has had multiple commits since `9651362` (the corrective fix `f063448`, reconcile-script bug fixes `7cfc1e2` / `f6b8a86` / `5394d4e` / `27061fa`, incident-doc move `98efc8f`, drift detector `f6cefa7`). Rewriting history breaks every local clone, including any CI checkout / archived state.
3. **The educational signal is valuable.** The postmortem narrates Sonnet 4.6's mistake of committing plaintext credentials, citing this exact commit. Removing it from history weakens the "what we learned" story without improving security.
4. **No external attack value.** The credentials were for a dev/lab K3s cluster behind a private LAN/Tailscale boundary. Even when they were live, they were not exposed to the public internet.

## Conditions under which we WOULD do it

- The credentials had been deployed in a production / customer-facing system.
- The git history were public (the Asgard repo is private under `MegaWiz-Dev-Team`).
- An external compliance audit explicitly required scrubbing.
- The leaked values were of a kind that can't be rotated cheaply (e.g. long-lived hardware-backed keys).

None apply here.

## Ready-to-run command (if operator decides to override)

```bash
# Prerequisites: every clone-holder must be notified BEFORE you run this.
# After you push, they must run `git fetch && git reset --hard origin/<branch>`
# or re-clone — their existing checkout will diverge irreversibly.

cd /Users/mimir/Developer/Asgard

# Install git-filter-repo if missing
brew install git-filter-repo

# Scrub the leaked literals from history (creates new SHAs from 9651362 onward)
cat > /tmp/asgard-scrub.txt <<'EOF'
REDACTED-MARIADB-PW==>REDACTED-MARIADB-PW
REDACTED-NEO4J-PW==>REDACTED-NEO4J-PW
EOF

git filter-repo --replace-text /tmp/asgard-scrub.txt --force

# git filter-repo wipes the origin remote — add it back
git remote add origin https://github.com/MegaWiz-Dev-Team/Asgard.git

# Force-push the rewritten branch
git push --force-with-lease origin docs/sprint-52-plan-adr-008

# Tell GitHub to garbage-collect the orphaned commits in its pack
# (this still does not remove them from any local clones)
gh api -X POST /repos/MegaWiz-Dev-Team/Asgard/git/refs \
  -f ref="refs/heads/scrub-trigger" -f sha="$(git rev-parse HEAD)" && \
gh api -X DELETE /repos/MegaWiz-Dev-Team/Asgard/git/refs/heads/scrub-trigger
```

## Review trigger

Re-evaluate this decision if:
- The Asgard repo becomes public.
- The same class of leak happens again with credentials that can't be rotated.
- A compliance regime (HIPAA / PCI-DSS / SOC2) is adopted that prescribes scrubbing.
