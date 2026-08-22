# Repository Visibility Flip Checklist

> Use this **every time** an Asgard-family repo flips from private → public.
> Born from INC-2026-05-10-O1 (Sprint 51d open-core go-live secret burn).

## Why this exists

Pre-commit hooks (gitleaks, detect-private-key) prevent NEW commits with
inline secrets. They say nothing about HISTORICAL commits. When a repo
flips public, every byte of every historical commit is now world-readable.

INC-2026-05-10-O1 postmortem L1: **"Repo visibility flip is a security
event, not a release event."** This checklist enforces that.

## When to use this checklist

- [ ] Flipping repo from `private` → `public`
- [ ] Flipping repo from `private` → `internal` (org-visible)
- [ ] Granting first external collaborator access to a previously
      org-only repo
- [ ] First mirror of repo to a public registry (ghcr.io / crates.io)
- [ ] Releasing first artifact built from previously-private code

## Pre-flip steps (mandatory)

### 1. Scan ALL history for secrets

```bash
# gitleaks across full history (NOT just current state)
gitleaks detect --source . --log-opts="--all" --report-format json \
  --report-path /tmp/preflip-gitleaks.json --no-git --redact

# Trufflehog second-pass (different detector matrix)
trufflehog git file://. --no-update --json > /tmp/preflip-trufflehog.json
```

Required outcome: **zero findings** in either tool, OR every finding
explicitly classified as a false positive in a written remediation note.

### 2. For each real finding — rotate BEFORE flip

Do NOT flip with un-rotated secrets in history. Specifically:

- Database passwords → rotate, update K8s Secret, restart consumers
- API keys → rotate at issuer (Heimdall / Zitadel / cloud provider) + update Secret
- OIDC client secrets → rotate via Zitadel UI + update Secret + restart consumers
- Master encryption keys → rotation is multi-step; defer flip until done OR audit shows low-risk defer is OK (per INC-2026-05-10 Option 8A pattern)
- Signed certs / private keys → reissue + rotate

For each rotation, follow the `docs/security/ROTATION-PLAN-*.md` template
shape — dependency-ordered, with verify-and-rollback steps per item.

### 3. Verify chart / manifests use `secretKeyRef`, not inline

```bash
# Quick audit — any inline plaintext in K8s manifests?
grep -rE "value:\s*[\"'][A-Za-z0-9+/=]{16,}" k8s/ charts/ \
  | grep -v "valueFrom:" | grep -v "^.*://"
```

Anything matching → migrate to `secretKeyRef` against `asgard-secrets`
or equivalent. K8s manifests committed to a public repo should NEVER
have inline credentials, even encrypted ones.

### 4. Verify pre-commit hooks are installed (regression prevention)

```bash
pre-commit run --all-files
```

Must show gitleaks + detect-private-key + check-added-large-files PASS.

### 5. Verify CODEOWNERS / branch protection are in place

For security-sensitive files (anything in `docs/security/`, `charts/asgard/values.yaml`,
`k8s/04-security/`), require approver = security reviewer.

```bash
gh api repos/MegaWiz-Dev-Team/<repo>/branches/main/protection \
  --jq '.required_pull_request_reviews'
```

### 6. Decide on Step 8-style deferrals up-front

For high-disruption rotations (master keys, root certs), decide
**before the flip** whether the rotation cost > residual risk. Document
the decision (Option 8A pattern). Do not let "we'll get to it later"
mean "we never did".

## At-flip steps

### 7. Pick a low-traffic window

Visibility flip is metadata-only on GitHub but takes effect immediately.
If anyone discovers the burned-but-then-rotated history in the window
between flip and remediation completion, the audit story becomes more
complex. Pick a window where the team is available for ~2h post-flip.

### 8. Flip + announce internally

```bash
gh repo edit MegaWiz-Dev-Team/<repo> --visibility public
```

Then: announce to the team in Slack / Discord / equivalent. Include:
- Confirmation that pre-flip checklist is complete
- Link to the most recent rotation report (if any)
- Who's on watch for the next 2h

### 9. Verify post-flip artifacts

- [ ] Repo is publicly visible at `https://github.com/MegaWiz-Dev-Team/<repo>`
- [ ] LICENSE file is present and matches policy (per `memory/feedback_asgard_license`)
- [ ] README is suitable for external readers (no internal-only refs)
- [ ] Default branch is protected (branch protection rules still active)
- [ ] Issues / Discussions enabled (or explicitly disabled with rationale)
- [ ] No CI secrets / environment variables visible in workflow logs

## Post-flip steps (within 24h)

### 10. File an incident bundle if any rotation was triggered

If any secret was rotated as part of the flip, file the rotation as an
incident per `memory/asgard_incident_docs` convention:

```
docs/incidents/<YYYY-MM-DD>-<slug>/
├── README.md
├── incident-report.md
├── postmortem.md
└── compliance-response.md
```

INC-2026-05-10-O1 is the reference implementation.

### 11. Verification pass at T+7d

Schedule a follow-up review 7 days after flip:
- All rotated secrets still in use (no consumer reverted to old key)?
- Any external observation of the burned history (security advisory, abuse signal)?
- Compensating control (gitleaks pre-commit) still active on all dev workstations?

### 12. Update this checklist if anything was missed

If the flip surfaced any new failure mode, append it as a step here.
This checklist is a living document.

## What NOT to do

- ❌ **Do NOT** force-push history rewrite to scrub burned secrets after the flip.
  Cost (breaking external commit-hash references, CI re-runs, potential reflog
  archaeology) > benefit. The rotated secret is dead; its public presence in
  history is informational, not active.
  (INC-2026-05-10 chose this path; rationale documented.)
- ❌ **Do NOT** rely solely on "we'll notify customers if anything bad happens".
  Pre-emptive rotation is the control; notification is the audit trail.
- ❌ **Do NOT** flip the visibility before the rotation plan is fully drafted.
  Rotation plan = pre-flip artifact. No plan = no flip.

## Related documents

- `docs/security/ROTATION-PLAN-*.md` — per-incident rotation playbook (template at `ROTATION-PLAN-2026-05-10.md`)
- `docs/incidents/2026-05-10-open-core-go-live-burn/postmortem.md` — incident that birthed this checklist (L1-L5 lessons)
- `.pre-commit-config.yaml` — gitleaks + detect-private-key + check-added-large-files (regression prevention)
- `memory/asgard_incident_docs` — incident-docs convention

## Sign-off

```
Engineering lead:  _____________________  Date: __________
Security review:   _____________________  Date: __________
Pre-flip checklist completed: yes [ ] no [ ]
Rotation plan reference: _______________
```
