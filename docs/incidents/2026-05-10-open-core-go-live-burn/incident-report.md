# Incident Report — INC-2026-05-10-O1

**Incident ID**: INC-2026-05-10-O1
**Severity**: SEV-2 (latent exposure; no observed exploitation)
**Reported**: 2026-05-10 (at moment of repo visibility flip)
**Reporter**: Engineering (pre-go-live security review)
**Status**: Closed 2026-05-19 (recovery complete; Step 8 formally deferred per audit)

## Summary

At Sprint 51d open-core go-live, the `MegaWiz-Dev-Team/Asgard` repository was
flipped from private to public. A pre-existing commit (`73a004f`) contained
plaintext secrets inlined in K8s manifests and umbrella chart values:
Heimdall API key, Neo4j password, MariaDB user password, Postgres password
(Zitadel DB), Yggdrasil OIDC client secrets (Mimir + Eir), Laminar API key,
and Yggdrasil masterkey. PR #31 (merged before go-live) had refactored the
chart to read from a K8s Secret, but the values committed in earlier history
remained accessible in the now-public history.

The repository was made public knowingly; the burn was the secondary effect
of pre-existing inline values combined with that visibility flip.

## Detection

- **How detected**: Engineering pre-go-live security review enumerated all
  known-risky paths against the repo's pending public state. The chart values
  / manifest history showed the inline plaintext.
- **Time to detection**: T+0 (moment of visibility flip; review was the
  trigger to make the flip).
- **External observation**: None reported. No public disclosure, no security
  advisory filed against Asgard from third parties.

## Scope of exposure

Secrets reachable in public git history at commit `73a004f`:

| Secret | Storage at moment of leak | Risk profile |
|---|---|---|
| HEIMDALL_API_KEY | inline in `charts/asgard/values.yaml` | API to Heimdall LLM gateway — could exhaust budget or proxy abuse if leak were observed |
| NEO4J_PASSWORD | inline | Read access to KG including PrimeKG + tenant entities |
| MARIADB_PASSWORD | inline | Mimir database read/write incl. PHI |
| YGGDRASIL_POSTGRES_PASSWORD | inline | Zitadel auth backing store (encrypted) |
| YGGDRASIL_CLIENT_SECRET (Mimir) | inline | OIDC auth for Mimir UI |
| EIR_CLIENT_SECRET | inline | OIDC auth for Eir/OpenEMR |
| LAMINAR_API_KEY | inline | Observability ingest token |
| YGGDRASIL_MASTERKEY | inline (placeholder `yggdrasil-masterkey-change-me-ok`) | Zitadel encryption key for IDP/SMTP secrets |

**Mitigating factors at time of incident**:
- Cluster ingress was Tailscale-only (no public network paths to most services)
- Yggdrasil masterkey was the placeholder `yggdrasil-masterkey-change-me-ok` —
  literal default, not a high-entropy value
- No external IDP credentials or SMTP relays had been added to Zitadel yet
  (the masterkey protected mostly empty encrypted fields)

## Immediate response

| Time (T+) | Action |
|---|---|
| T+0:30 | `docs/security/ROTATION-PLAN-2026-05-10.md` drafted with 8-step dependency-aware execution order |
| T+1d AM (2026-05-11) | Phase B rotation begins: Step 2 (Heimdall API key, dual-key zero-downtime), Step 4 (Neo4j), Step 5 (MariaDB), Step 6 (Postgres), Step 7a (Mimir-OIDC) |
| T+1d PM | Final session pass: Step 3 (Laminar — DB sha3-256 hash rotation + ConfigMap + Secret + restart), Step 7b (Eir-Gateway — OpenEMR CryptoGen-encrypted client secret + env migration to secretKeyRef) |
| T+2d (2026-05-12) | Sprint 50 unrelated work ships; cluster verified post-rotation; PR #31 chart refactor confirmed effective |
| T+7d (2026-05-17) | Sprint tracker doc refreshed; rotation captured in main sprint planning |
| T+9d (2026-05-19) | Verification pass confirms 7/8 rotations stable; Step 8 (Masterkey) formally deferred per Option 8A (encrypted-data audit shows low risk) |

## Bonus fixes during incident response

Three pre-existing latent issues were discovered and fixed during rotation:

1. **Heimdall outage ~16 min (2026-05-11 08:37 ICT)** — `com.asgard.lan-bridge-http`
   plist port-8080 was a known mistake from 2026-05-09 that had never been
   cleaned up. Heimdall crashed during restart → lan-bridge socat won the
   port race → Heimdall couldn't rebind. Cleaned up via plist bootout.
2. **Mimir-Neo4j 401 pre-existing** — `mimir-api` was using `REDACTED-PW`
   placeholder (Phase A migration had pulled wrong env value). Real Neo4j
   password was `asgard_neo4j_password` from `NEO4J_AUTH` env. Step 4 fixed
   both Neo4j and Mimir-api in lockstep.
3. **Bifrost DATABASE_URL inline plaintext** — Phase A had only covered
   Yggdrasil/Mimir-api/Mimir-dashboard. Bifrost still had inline
   `DATABASE_URL` with old `mimir_password`. Step 7a unmasked it (Bifrost
   crashed post-restart). Migrated to `valueFrom: secretKeyRef
   MIMIR_DATABASE_URL`.

## Current status (2026-05-19 verification pass)

- ✅ 7 of 8 rotation steps complete and verified live
- ⏸ Step 8 (Yggdrasil masterkey) deferred per Option 8A — encrypted-data
  audit shows 3 OIDC + 6 API client + 1 machine user secrets in Zitadel DB.
  After Step 7a rotation, the most-valuable encrypted columns hold
  post-rotation values. Threat surface remains small (cluster
  Tailscale-only). Re-encryption sweep is risk > benefit at this point.
- ✅ Compensating control already in place pre-incident: `.pre-commit-config.yaml`
  with gitleaks v8.21.2 + detect-private-key + check-added-large-files +
  check-merge-conflict hooks. New commits with inline secrets fail at
  commit time.

## Open items

| # | Item | Owner | Trigger to action |
|---|---|---|---|
| 1 | Step 8 Masterkey rotation | TBD | When external IDP creds or SMTP relays are added to Zitadel |
| 2 | Laminar SHARED_SECRET_TOKEN placeholder cleanup | TBD | Separate finding (NOT this incident scope) — see `docs/security/laminar-shared-secret-token-cleanup-draft.md` |
| 3 | Verify pre-commit hook is installed on all engineer workstations | Engineering lead | One-shot audit |
