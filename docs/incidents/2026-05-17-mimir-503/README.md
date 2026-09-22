# INC-2026-05-17-001 — Mimir 503 Outage

| | |
|---|---|
| **Severity** | P1 (full Mimir API outage) |
| **Detection** | User report, 2026-05-17 01:00 UTC+7 |
| **Resolved** | 2026-05-17 08:06 UTC+7 |
| **User-visible duration** | 4h 6m |
| **MTTR (diagnosis → verify)** | 91 min |
| **Status** | Resolved; O2 / O6 / Mimir-migration follow-ups still pending |

## Files in this folder

- [`incident-report.md`](./incident-report.md) — chronological technical narrative + commands used during recovery.
- [`postmortem.md`](./postmortem.md) — 5 Whys, root causes, AI-assisted-response model comparison (Haiku 4.5 → Sonnet 4.6 → Opus 4.7), execution log (E1–E5 bugs discovered while running the remediation), final status table.
- [`compliance-response.md`](./compliance-response.md) — ISO 27001:2022 Annex A.16 + ISO 29110:2021 mapping for the incident.
- [`blog-draft-v1-haiku.md`](./blog-draft-v1-haiku.md) — original (Haiku 4.5) blog draft, kept as historical evidence of the misattributed root cause (Docker Compose). The version published at `asgard.megawiz.co.th/blog/mimir-4hr-outage-postmortem` is a later rewrite that tells the full three-model story.

## Outstanding follow-ups (from postmortem)

- **O2** — strip leaked commit `9651362` from git history (credentials rotated, force-push optional but recommended).
- **O6** — Sprint 52 ticket: wire Fafnir Vault → External Secrets Operator so this class of bug stops being possible.
- **Mimir migration mystery** — same image SHA, different behavior between old/new pods on `migration 20260516000001 missing in resolved`. Needs source-code investigation.
- **Drift detector** — add validation Check 7 to flag live deployment ↔ committed manifest divergence (e.g. `envFrom` stripped from Bifrost).

## Related artifacts

- Validation script: [`../../../scripts/validate-k8s-before-deploy.sh`](../../../scripts/validate-k8s-before-deploy.sh)
- Rotation scripts: [`../../../scripts/rotate-mariadb-password.sh`](../../../scripts/rotate-mariadb-password.sh), [`../../../scripts/rotate-neo4j-password.sh`](../../../scripts/rotate-neo4j-password.sh)
- Secret-management policy: [`../../security/SECRETS.md`](../../security/SECRETS.md)
- Recovery runbooks: [`../../../RECOVERY_RUNBOOKS.md`](../../../RECOVERY_RUNBOOKS.md)
- Deployment checklist: [`../../../DEPLOYMENT_CHECKLIST.md`](../../../DEPLOYMENT_CHECKLIST.md)
