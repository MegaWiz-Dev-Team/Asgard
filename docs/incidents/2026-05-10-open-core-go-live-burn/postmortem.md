# Postmortem — INC-2026-05-10-O1

**Date drafted**: 2026-05-20
**Drafted by**: Engineering
**Reviewed by**: pending
**Blameless format**: yes (per Asgard convention)

## What happened (one sentence)

On Sprint 51d open-core go-live, the Asgard repository was flipped from
private to public while pre-existing inline plaintext secrets remained in
git history at commit `73a004f`, exposing 8 credentials whose rotation
became necessary.

## Root cause

**Two-factor latent risk realized at go-live**:

1. **The secret-in-source antipattern was tolerated during private-repo
   phase**. Chart values and K8s manifests carried inline plaintext for
   convenience — acceptable in a closed-source private repo, catastrophic
   if visibility changes.
2. **PR #31 chart refactor (Secret extraction) happened TOO LATE relative to
   the visibility flip**. PR #31 moved values to K8s Secret references, but
   the historical commits still held the inline values. Once history is
   public, the burn is realized — the present-state cleanup didn't undo it.

The actual technical fix (PR #31) was correct. The miss was the **ordering**:
chart refactor should have happened, the burned secrets should have been
rotated, AND THEN the visibility flip should have happened. Instead the
visibility flip was the trigger that promoted the latent risk to live risk.

## Why didn't compensating controls prevent this?

The `.pre-commit-config.yaml` with gitleaks v8.21.2 was present at incident
time. It would have prevented NEW commits with inline secrets. It does NOT
remediate HISTORICAL commits — those are immutable once made (force-push
history rewrite is possible but was deliberately avoided to preserve commit
hashes referenced by external CI / external observers).

In other words: gitleaks prevented the next leak, not the existing one.

## Timeline (already documented in incident-report.md)

See [`incident-report.md`](incident-report.md) "Immediate response" section.

## What went well

1. **Pre-go-live security review caught the burn at T+0**. The review was the
   reason the flip was scheduled — it surfaced the inline secrets before any
   user-visible deploy that would have made them more valuable to an
   attacker.
2. **Rotation plan was drafted within 30 minutes**. `ROTATION-PLAN-2026-05-10.md`
   captured all 8 steps in dependency order with verify-and-rollback details
   per step.
3. **Phase B execution was disciplined**. 5/7 steps cleanly done day 1;
   final 2 (Step 3 Laminar + Step 7b Eir) finished same-day in a late
   session pass. Zero data loss across rotation.
4. **Bonus fixes uncovered during rotation** (lan-bridge cleanup,
   Mimir-Neo4j 401, Bifrost DB inline migration) were addressed in
   lockstep, leaving the cluster cleaner than before the incident.
5. **Verification pass at T+9d** confirmed all rotations were stable AND
   independently caught a separate item (Laminar SHARED_SECRET_TOKEN
   placeholder) that was correctly classified as out-of-scope and routed
   to its own follow-up.

## What went badly

1. **The window between PR #31 merge and the visibility flip was too tight**.
   PR #31 was merged the same day as the flip. There was no time for
   historical-secret rotation between "chart refactor" and "go public".
2. **Step 8 (Yggdrasil masterkey) is still deferred**. The audit-based
   defer (Option 8A) is reasonable, but it's an open item — a future event
   that adds external IDP creds or SMTP relays to Zitadel will require
   coming back to this.
3. **No formal incident bundle existed for 9 days**. Recovery was tracked
   in `docs/security/ROTATION-PLAN-2026-05-10.md` + ad-hoc memory entries,
   not in the `docs/incidents/` convention. This bundle (filed 2026-05-20)
   retroactively closes that gap.

## Lessons learned

### L1 — Repo visibility flip is a security event, not a release event

A private → public flip changes the threat model for every byte of every
file in every historical commit. It must be treated with the same rigor as
a deploy that exposes prod credentials.

### L2 — Compensating controls must cover history, not just current state

Gitleaks at pre-commit prevents future inline secrets. It says nothing about
the past. The visibility-flip checklist needs an explicit "scan ALL history,
rotate ANY identified secret BEFORE flipping" step.

### L3 — Rotation plans should always be dependency-ordered

`ROTATION-PLAN-2026-05-10.md` got the order right (Heimdall → Neo4j → DBs →
OIDC → masterkey). Result: no cascade failures. Future plans should keep
this shape.

### L4 — Verification passes 1+ week after incident close ARE necessary

The verification pass at T+9d (2026-05-19) revealed:
- The MEMORY.md index was stale relative to the actual rotation memory file
- A latent issue (Laminar SHARED_SECRET_TOKEN placeholder) that hadn't been
  noticed during rotation execution

Both were caught and routed. Periodic re-verification (e.g., monthly for
SEV-2+ incidents) catches drift between intent and reality.

## Action items

| # | Item | Owner | Status |
|---|---|---|---|
| AI-1 | Add "pre-flip scan ALL history for secrets" to repo-visibility-flip checklist | Eng lead | 📝 Draft (this incident's primary preventative) |
| AI-2 | Confirm gitleaks pre-commit is installed on all dev workstations | Eng lead | 📝 Pending |
| AI-3 | Step 8 Masterkey rotation when trigger condition fires | TBD | ⏸ Deferred per Option 8A |
| AI-4 | Laminar SHARED_SECRET_TOKEN cleanup (separate from this incident) | TBD | 📝 Draft filed |
| AI-5 | Decide whether to git-history-rewrite the burned secrets out (cost: breaks external commit-hash refs) vs accept-and-monitor | Eng lead | 📝 Pending decision |

## What we are NOT doing

- **Force-pushing rewritten history to scrub the burned commits**. Cost
  (breaking external commit-hash references, CI re-runs, potential reflog
  archaeology) judged greater than benefit (the burned secrets are all
  rotated; their public presence in history is informational, not active).
  If a regulator requests scrubbing, revisit. Otherwise: keep the history.
- **Notifying every external party who may have observed the public repo
  during the burn window**. No external party is currently known to have
  acted on the burned secrets; cluster ingress was Tailscale-only at time
  of burn; the threat surface was small. Public notification would create
  disproportionate alarm relative to actual exposure.

## Sign-off

```
Engineering lead:  _____________________  Date: __________
Security review:   _____________________  Date: __________
```
