# INC-2026-05-10-O1 — Open-core go-live secret burn

**Severity**: SEV-2 (no active exploitation observed; pre-emptive rotation required)
**Status**: ✅ Closed (recovery complete 2026-05-19, postmortem 2026-05-20)
**Sprint trigger**: 51d (open-core go-live) → 51e (recovery)
**Scope**: 7 secrets exposed in public git history. 1 deferred per audit (Option 8A).

## Index

- [`incident-report.md`](incident-report.md) — Detection, scope, immediate response
- [`postmortem.md`](postmortem.md) — Root cause, lessons, action items
- [`compliance-response.md`](compliance-response.md) — Regulatory + customer disclosure stance

## Quick facts

| Field | Value |
|---|---|
| Date detected | 2026-05-10 (at moment of repo visibility flip) |
| Repo affected | `MegaWiz-Dev-Team/Asgard` (umbrella + chart templates) |
| Burn vector | Commit `73a004f` (pre-existing inline secrets in K8s manifests + chart values) |
| Discovery | Pre-go-live security review — visibility flip from private → public surfaced existing inline secrets in git history |
| Rotation plan | `docs/security/ROTATION-PLAN-2026-05-10.md` |
| Recovery status | **7/8 rotations done** as of 2026-05-19; Step 8 Masterkey deferred per Option 8A (encrypted-data audit shows low risk; revisit when external IDP creds added to Zitadel) |
| Compensating control | `.pre-commit-config.yaml` with gitleaks v8.21.2 + detect-private-key hooks — present pre-incident, prevents future regressions |

## Timeline summary

```
2026-05-10  T+0    Repo flipped public — burn moment
2026-05-10  T+0:30 ROTATION-PLAN-2026-05-10.md drafted
2026-05-11  AM     Phase B rotation execution starts (Steps 2, 4, 5, 6, 7a)
2026-05-11  PM     Final session pass — Steps 3, 7b completed
2026-05-12         Sprint 50 ships unrelated work; cluster verified post-rotation
2026-05-17         Sprint tracker doc refresh, captures rotation in main sprint planning
2026-05-19         Verification pass — confirmed 7/8 done; Step 8 deferred decision
2026-05-20         This incident bundle filed (closing per Asgard incident convention)
```

## Related artifacts

- `docs/security/ROTATION-PLAN-2026-05-10.md` — execution plan with all 8 steps
- `docs/sprint-planning.md` — Sprint 51e status row
- `docs/security/laminar-shared-secret-token-cleanup-draft.md` — separate finding (NOT part of this incident), tracked independently
- `memory/rotation_2026_05_11_status.md` (Mimir-side memory) — operator-level rotation notes
