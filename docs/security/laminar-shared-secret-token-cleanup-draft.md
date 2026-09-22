# Laminar SHARED_SECRET_TOKEN cleanup — issue draft

> **Status**: DRAFT — not yet filed. Created 2026-05-20 from rotation verification pass.
> **Source**: `memory/rotation_2026_05_11_status.md` "Verification pass 2026-05-19" section.
> **Action required**: human review → file as Asgard issue (or skip if accepted as-is).

## Summary

`laminar-app-server` deployment ships with hardcoded plaintext placeholder
in its `SHARED_SECRET_TOKEN` env var:

```
SHARED_SECRET_TOKEN=asgard_laminar_secret_token_placeholder
```

This is the otel-collector ↔ laminar internal authentication token,
separate from the `project_api_keys` table that was rotated in Sprint 51e
Step 3 on 2026-05-11.

## Why this is NOT a Sprint 51e burn-recovery item

Sprint 51e Step 3 rotated the user-facing API key (sha3-256 hash in
`project_api_keys.hash` + `shorthand` + `asgard-secrets.LAMINAR_API_KEY`
slot + otel-collector ConfigMap). That's the leaked credential from the
public-repo commit `73a004f` accident.

`SHARED_SECRET_TOKEN` is a separate internal token — a placeholder
shipped with the open-core Laminar chart that nobody changed during
initial deployment. Not in git history; not leaked; not part of the
burn-recovery scope.

## Risk profile

| Dimension | Assessment |
|---|---|
| Exposure | Internal cluster only — Tailscale subnet ingress, no public route |
| Data sensitivity | Trace / observability data only (no PII per `feedback_include_tyr_in_pii_designs` |
| Authentication chain | otel-collector → laminar-app-server, in-cluster only |
| Attack surface | Requires existing cluster network access first |
| Burn from git? | NO — placeholder is in chart values, never a real production credential |

**Severity**: Low. Cleanup is best-practice hygiene, not active vulnerability.

## Proposed fix

1. Generate real token: `openssl rand -hex 32`
2. Patch `asgard-secrets` to add new slot, e.g. `LAMINAR_SHARED_SECRET_TOKEN`
3. Update Laminar Helm chart values (or umbrella chart override) — replace
   `SHARED_SECRET_TOKEN` literal with `valueFrom.secretKeyRef`
4. Update otel-collector ConfigMap to reference same secret (matching value)
5. Restart laminar-app-server + otel-collector
6. Verify trace ingestion still works

**Effort**: ~15 minutes by someone with K8s + helm access.
**Risk**: Brief outage if otel-collector and laminar-app-server pick up
new token at different times. Mitigate by patching both Secret + ConfigMap
in one apply, then rolling restart.

## When NOT to do this

- If Laminar is about to be renamed-and-rebuilt as `heimdall-trace`
  submodule per `memory/asgard_laminar_saga.md` (Sprint 56 territory),
  defer until that work happens — fix the placeholder there as part of
  the rename PR.

## References

- `memory/rotation_2026_05_11_status.md` (Verification pass 2026-05-19)
- `memory/asgard_laminar_saga.md` (Laminar → heimdall-trace rename)
- `docs/security/ROTATION-PLAN-2026-05-10.md` (Sprint 51e burn-recovery scope)
