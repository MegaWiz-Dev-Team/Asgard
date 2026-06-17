# ADR-022: SMART on FHIR 2.0 Launch and Authorization Architecture

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Locks the SMART on FHIR 2.0 implementation across Yggdrasil (authorization), `mimir-fhir` (discovery + scope enforcement), Bifrost (launch handler + CDS Hooks endpoint), Hermodr (token-aware MCP tool calls), and eir-gateway (OpenEMR integration). Defines the four supported client types — OpenEMR EHR launch, standalone web, CDS Hooks service, and Backend Services — and their authentication paths. Unblocks Sprint 9 (Smart-on-FHIR + OpenEMR integration) and the Sprint 59 CDS pilot production deploy.
**Related:** [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md), [ADR-012](ADR-012-fhir-native-data-plane-no-ehr-replacement.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-016](ADR-016-asgard-fhir-profile-family.md), [ADR-018](ADR-018-cds-cqm-as-eir-agent-family.md), [ADR-019](ADR-019-fhir-profile-validation-tightest-binding-wins.md), [ADR-020](ADR-020-43files-hosxp-fhir-adapter.md)

## Context

Asgard runs **inside** the hospital's EHR per [ADR-012](ADR-012-fhir-native-data-plane-no-ehr-replacement.md). Layer 2 modules (Eir agents, CDS Cards, care pathways, CQM dashboards) need to be launched from the EHR with patient context already selected, plus the modules must call back into `mimir-fhir` REST with a token scoped to the patient under care.

The HL7 SMART App Launch 2.0 specification is the industry standard for this pattern. It layers OAuth2 (authorization code flow with PKCE) on top of FHIR with conventions for: launch parameter passing, scope vocabulary (`patient/*.read`, `launch/patient`, `system/*.read`, etc.), token claims (patient context, `fhirUser`), and a `/.well-known/smart-configuration` discovery endpoint.

Asgard already has the OAuth2 building blocks:

- **Yggdrasil** (Zitadel-based) issues RS256 JWTs with `urn:zitadel:iam:org:id → tenant_id` claim per the existing JWT auth pattern.
- **eir-gateway** has OpenEMR integration that handles existing API calls.

Sprint 9 layers SMART semantics over these — not greenfield. Without an architecture lock, Sprint 9 risks: (a) bypassing Yggdrasil with a parallel auth path, (b) leaking patient context out-of-band via headers, (c) embedding CDS Hooks auth inside SMART when the specs differ, (d) Backend Services authentication using insecure shared secrets.

## Decision

Implement SMART on FHIR 2.0 across the existing Asgard components, supporting four client types. Use a hybrid token model (5-minute access token + refresh), static client registration for Phase 1, and resource+operation-level scope enforcement.

### D1. Discovery endpoint on `mimir-fhir`

`mimir-fhir` exposes the SMART discovery document at:

```
GET /fhir/R5/.well-known/smart-configuration
```

Returns JSON conforming to [SMART 2.0 Configuration](https://hl7.org/fhir/smart-app-launch/conformance.html), including:

- `authorization_endpoint` = `https://yggdrasil.{customer}.asgard.megawiz.co.th/oauth/v2/authorize`
- `token_endpoint` = `https://yggdrasil.{customer}.asgard.megawiz.co.th/oauth/v2/token`
- `introspection_endpoint` = `.../oauth/v2/introspect`
- `revocation_endpoint` = `.../oauth/v2/revoke`
- `scopes_supported` = the Asgard scope set (D6)
- `capabilities` = `launch-ehr`, `launch-standalone`, `authorize-post`, `permission-patient`, `permission-user`, `client-confidential-symmetric`, `client-confidential-asymmetric`, `permission-v2`
- `code_challenge_methods_supported` = `["S256"]` (PKCE mandatory)
- `token_endpoint_auth_methods_supported` = `["client_secret_post", "private_key_jwt"]` (private_key_jwt for Backend Services)

`mimir-fhir` does NOT proxy authentication. The discovery endpoint is the only SMART-aware surface on `mimir-fhir`; everything else is the FHIR REST API + the scope enforcement middleware (D6).

### D2. Authorization on Yggdrasil

Yggdrasil's Zitadel instance handles all OAuth2 flows. Zitadel is extended with:

- Client definitions per the static registration (D5)
- Custom token claim mapping to add SMART-specific claims (`patient`, `fhirUser`, `scope`, `aud`)
- Audience restriction: tokens issued for `mimir-fhir` carry `aud=mimir-fhir.{customer}.asgard.megawiz.co.th`

The existing tenant_id propagation (`urn:zitadel:iam:org:id → tenant_id`) is preserved unchanged — SMART claims are additive, not a replacement.

### D3. Hybrid token model — 5-minute access token + refresh

| Token | Lifetime | Issuance | Reason |
|---|---|---|---|
| Access token (JWT) | 5 minutes | OAuth2 token endpoint | Short enough for revocation within clinical session timeout; long enough to avoid refresh on every FHIR call |
| Refresh token | 24 hours (clinical) / 30 days (admin standalone) | OAuth2 token endpoint, same response | Allows session continuity across patient visits without re-launch |
| Backend Services JWT (for asserting client identity) | 5 minutes | Self-asserted by client per RFC 7523 | No refresh; client re-asserts on each token request |

Access token is **fat** — patient context, scopes, fhirUser, tenant, and audience all in claims. This means hot-path FHIR calls do not hit Yggdrasil. Revocation latency is bounded by access token TTL (5 min). Refresh tokens are stored in the client (server-side confidential) and exchanged via the token endpoint.

The 5-minute TTL is a deliberate trade between hot-path performance (no per-request introspection) and revocation responsiveness (≤5 min from clinician logout to access termination). Per existing Cloudflare-free-tier 100s timeout, no streaming endpoint will exceed the access token lifetime within a single response.

### D4. Two launch modes — EHR launch + Standalone

**EHR launch** (primary use case — clinician inside OpenEMR):

```
OpenEMR doctor opens patient chart
  → clicks Asgard app button (e.g. "Asgard CDS", "Eir DDx")
  → OpenEMR generates launch URL:
      https://bifrost.{customer}/smart/launch
        ?iss=https://mimir-fhir.{customer}/fhir/R5
        &launch=<opaque-context-id>
  → Bifrost /smart/launch resolves launch context (patient_id, encounter_id, user_id)
  → redirects to Yggdrasil /authorize with launch context cookie
  → Yggdrasil auth + consent (skipped for pre-trusted EHR launches)
  → returns authorization code to Bifrost callback
  → Bifrost exchanges code → access_token (with patient claim)
  → Bifrost renders Asgard app (CDS card, Eir UI, etc.) with token
```

**Standalone launch** (admin / QI / CQM dashboard use case):

```
User navigates to https://asgard-portal.{customer}/login
  → portal redirects to Yggdrasil /authorize
  → user authenticates with their hospital credentials (via Zitadel idp)
  → portal receives access_token (no patient claim — user picks patient via FHIR search)
  → portal can elevate scope via separate "select patient" flow that re-issues
    token with patient claim if the user has user/Patient.read scope
```

Both modes use the **same Yggdrasil endpoints** and the **same token format**. The difference is in launch context provisioning (EHR provides it; standalone defers to user action).

### D5. Static client registration — 3 pre-registered clients

Phase 1 supports exactly three pre-registered client_ids per deployment. Self-service / Dynamic Client Registration (RFC 7591) is rejected — single Mac mini per customer ([ADR-009](ADR-009-single-tenant-mac-mini-deployment.md)) means the customer's deployment is the only registration scope, and the apps within it are fixed.

| client_id | Type | Auth method | Used by |
|---|---|---|---|
| `asgard-cds` | Confidential, EHR-launch | `client_secret_post` | CDS Card UI surface (Sprint 59 outputs) |
| `asgard-eir-ui` | Confidential, both launch modes | `client_secret_post` | Eir agent UI (DDx, care pathway, CQM dashboards) |
| `asgard-admin` | Confidential, standalone only | `client_secret_post` | Admin / QI dashboards |

Backend Services use a separate authentication path (D8) — they do not appear in this client list.

Client secrets are managed in Vault (existing Asgard pattern), rotated per the existing rotation policy.

### D6. Scope enforcement — resource + operation level

Asgard implements SMART 2.0 v2 scope vocabulary (`permission-v2` capability). Supported scope tokens:

**User-context scopes** (with launch-standalone):
- `user/Patient.read`, `user/Observation.read`, `user/Condition.read`, etc.
- `user/*.read` (all resources, read-only)

**Patient-context scopes** (with launch/patient):
- `patient/Patient.read`, `patient/Observation.read`, ...
- `patient/*.read`
- Resource-scoped tokens reject any FHIR request for resources outside the bound patient — enforced in `mimir-fhir` REST middleware

**System-context scopes** (Backend Services):
- `system/Patient.read`, `system/Observation.read`, ...
- `system/*.read` / `system/*.write` (full read / write for ingest paths)

**Special scopes**:
- `launch`, `launch/patient`, `launch/encounter`
- `openid`, `fhirUser` (per SMART for user identity)
- `offline_access` (issues refresh token)

Field-level scope (e.g., hide allergies under low-trust) is **not** supported in Phase 1. Standard SMART does not define it and Asgard does not yet need it.

Scope enforcement happens in a single `mimir-fhir` REST middleware. Hermodr inherits the scope check by passing tokens through to `mimir-fhir` — Hermodr does not re-implement scope logic.

### D7. Patient context binding via signed token claim

Patient context lives in the access token JWT claim `patient`, signed by Yggdrasil:

```json
{
  "iss": "https://yggdrasil.{customer}/oauth/v2",
  "aud": "mimir-fhir.{customer}.asgard.megawiz.co.th",
  "sub": "user-uuid",
  "tenant_id": "asgard_medical",
  "patient": "Patient/123e4567-...",
  "encounter": "Encounter/abc-...",
  "fhirUser": "Practitioner/doctor-...",
  "scope": "patient/*.read launch/patient openid fhirUser offline_access",
  "iat": ..., "exp": ...
}
```

The `patient` claim travels the entire request path: OpenEMR → Bifrost → mimir-fhir → Hermodr → Eir. No component reads patient_id from headers or cookies. This:

- Prevents patient context tampering (signed)
- Propagates Skuggi PII gate context automatically (Skuggi reads `patient` claim from token)
- Makes audit straightforward — Tyr extracts `patient` claim hash + `fhirUser` from every request

Token validation in `mimir-fhir` and Hermodr verifies signature against Yggdrasil JWKS (cached). Audience check enforces `aud=mimir-fhir.{customer}`.

### D8. SMART Backend Services for system clients (RFC 7523 + private_key_jwt)

System clients — `mimir-43files-adapter` (Sprint 8 ingest), `eir-cqm` batch (Sprint TBD CQM) — use SMART Backend Services profile:

1. Each system client owns an asymmetric key pair (private key in Vault).
2. Client registers public key (JWK) with Yggdrasil at deployment time (static).
3. To obtain a token, client constructs a self-signed JWT assertion (per RFC 7523) and POSTs to Yggdrasil token endpoint with `grant_type=client_credentials` + `client_assertion`.
4. Yggdrasil verifies the assertion against the registered public key, issues access token with `system/*` scope.
5. Token used to call `mimir-fhir` REST.

No shared secrets on disk — only private keys (which Vault rotates) and Yggdrasil's registered public key. Asymmetric auth is mandatory for Backend Services. `client_secret_post` is forbidden for `system/*` scope clients.

This unblocks the Sprint 8 43Files adapter from using "fake" admin credentials. The adapter is a first-class SMART Backend Services client.

### D9. CDS Hooks authentication — hybrid

CDS Hooks 2.0 defines its own JWT-based authentication for the EHR-to-service hook firing direction (signed JWT in the Hook request payload). Asgard does **not** reuse SMART access tokens for hook firing — the specs are distinct.

However, CDS Hook service implementations (Asgard's hook responder) often need to fetch additional patient context via FHIR REST to formulate the Card. For this fetch, Asgard's `eir-cds-*` agents use a SMART access token issued through the standard flow.

Path:

```
OpenEMR fires CDS Hook
  → POST /cds-services/asgard-cds/medication-prescribe
    Header: Authorization: Bearer <CDS-Hooks-JWT>  (per CDS Hooks 2.0)
    Body: { context: { patientId, encounterId, draftOrder }, ... }
  → Bifrost CDS endpoint validates CDS Hooks JWT (against OpenEMR's published JWKS)
  → Bifrost obtains SMART access token via Backend Services flow (D8) for additional FHIR fetches
  → eir-cds-router uses SMART token to call mimir-fhir for full patient context
  → Returns CDS Card with link.url back to S55 PlanDefinition
```

CDS Hook fire authentication ≠ FHIR access authentication. Hybrid is the spec-correct posture.

### D10. Audit via Tyr

Every SMART event becomes a Tyr Wazuh event:

| Event | Fields |
|---|---|
| `smart.token.issued` | client_id, user_id (hash), patient_id (hash), scopes, ttl |
| `smart.token.refreshed` | client_id, user_id (hash), refresh count |
| `smart.token.introspected` | client_id, requester, result (active/inactive) |
| `smart.token.revoked` | client_id, user_id (hash), reason |
| `smart.token.expired_used` | client_id, request_path (alarm — late token use) |
| `smart.scope.denied` | client_id, requested_resource, requested_scope, granted_scopes (alarm — privilege violation attempt) |
| `smart.launch.opened` | client_id, launch_type (ehr|standalone), iss |

`smart.scope.denied` is a security event with alarm severity. Repeated `smart.token.expired_used` indicates a possible token reuse attack and triggers a Tyr rule.

## Why this architecture over alternatives

| Alternative | Reason rejected |
|---|---|
| Build a parallel auth path outside Yggdrasil | Two auth systems = inconsistent revocation, double Tyr audit, double key rotation pain |
| Long-lived tokens (1 hour+, no refresh) | PHI access — revocation latency must be bounded to ≤5 min clinical session timeout |
| Thin JWT with introspection on every call | +1 HTTP per FHIR call = 100s of ms added latency; CDS Hooks <3s budget would blow |
| Dynamic Client Registration in Phase 1 | Single Mac mini per customer; registration scope is bounded — DCR is overkill |
| Field-level scope (hide allergies on low trust) | Not standard SMART; complex to implement; no current customer ask |
| Patient context via header (X-Patient-Id) | Tamper-prone; doesn't propagate to Hermodr; no signature |
| Backend Services using shared secret | Shared secrets on disk are a credential leak vector; private_key_jwt is the SMART best practice |
| Unified CDS Hooks + SMART auth | CDS Hooks 2.0 fire is a different trust direction (EHR → Asgard) than SMART (Asgard → mimir-fhir); spec separation matters |
| Standalone launch deferred entirely | Admin / QI / CQM dashboards genuinely need it; deferring just relocates the work to Sprint 10 |

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Issue tokens that span multiple tenants | Single-tenant Mac mini per [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md); cross-tenant token = data plane violation |
| Persist refresh tokens in browser localStorage | Refresh tokens are confidential; live in server-side session store only |
| Skip PKCE | PKCE is mandatory in SMART 2.0; non-negotiable |
| Reuse OpenEMR's tokens directly without re-issuing through Yggdrasil | Asgard's tokens carry Asgard tenant + audience claims; OpenEMR's are not equivalent |
| Self-host FHIR `$validate` with relaxed mode for SMART clients | Validation is a deployment-wide guarantee per [ADR-019](ADR-019-fhir-profile-validation-tightest-binding-wins.md); no client gets a permissive mode |
| Skip audit for `system/*` scope (because batch) | Backend Services calls are the LARGEST volume — Tyr audit is most valuable there |

## Consequences

**Positive:**

- Spec-compliant SMART 2.0 — Asgard inter-operates with any SMART-aware EHR (OpenEMR, future HOSxP-FHIR-export, HAPI sandbox)
- Patient context signed end-to-end — Skuggi + Hermodr + Eir all see the same trusted context
- Hot path FHIR calls are stateless against Yggdrasil — performance preserved
- Backend Services authentication via private_key_jwt — no shared secrets on the on-prem disk
- Sprint 59 CDS unblocked — production deploy via OpenEMR EHR launch works after Sprint 9
- Sprint 8 mimir-43files-adapter unblocked from "use admin credentials" anti-pattern — it's a real SMART system client
- CQM batch (Sprint TBD) inherits the same Backend Services pattern — consistent operational story

**Negative:**

- 5-minute access token TTL means heavy users do refresh every 5 min — adds load to Yggdrasil (~12 refreshes/hr/user)
- Static client registration means changing app count requires a Yggdrasil config change + redeploy
- Refresh token storage in Bifrost session store is a new persistence concern (encrypted at rest)
- SMART Backend Services requires Vault to manage private keys per system client — adds key-rotation operational load
- Standalone launch in Sprint 9 adds 3-5 days vs EHR-launch-only

**Neutral / TBD:**

- Whether to implement SMART asymmetric client auth (`private_key_jwt`) for non-Backend-Services clients (e.g., for hospitals that disallow shared secrets) — defer until customer ask
- Whether to support `launch/encounter` scope in Sprint 9 — likely yes, but UI flow defers to Sprint 10
- Whether to publish a SMART conformance statement (separate document from FHIR conformance) — defer to Sprint 9 retro

## Sprint 9 deliverables

| Week | Days | Focus | Output |
|---|---|---|---|
| 1 | 1-2 | This ADR accepted; Yggdrasil Zitadel SMART claim mapping config; mimir-fhir `/.well-known/smart-configuration` endpoint | Discovery returns valid SMART 2.0 config; Yggdrasil issues tokens with `patient` + `fhirUser` claims |
| 1 | 3-5 | OAuth2 authorization code + PKCE in Bifrost `/smart/launch` handler | EHR launch end-to-end via test EHR (no UI yet) |
| 2 | 6-8 | mimir-fhir scope enforcement middleware (resource + operation level); audience verification | `patient/*.read` token rejects `patient/Account.read` |
| 2 | 9-10 | Hermodr token propagation to MCP tools; Skuggi reads `patient` claim | Eir agent receives signed patient context |
| 3 | 11-13 | OpenEMR client configuration + launch URL whitelist; eir-gateway launch dispatch | OpenEMR doctor clicks button → Asgard CDS UI loads |
| 3 | 14-15 | Asgard CDS UI shell (token-aware) + Eir UI standalone launch | Visual demo + standalone flow working |
| 4 | 16-17 | SMART Backend Services flow (private_key_jwt) for mimir-43files-adapter + eir-cqm | Sync runs use proper SMART system tokens |
| 4 | 18 | Refresh token endpoint + token introspection + revocation | Logout terminates session within 5 min |
| 4 | 19 | CDS Hooks separate JWT auth + hybrid SMART context fetch | Hook fires with EHR's JWT, agent fetches with SMART token |
| 4 | 20 | E2E test: OpenEMR → EHR launch → CDS Card; standalone → CQM dashboard; revocation → 5-min lockout; Sprint 59 unblock validated | Green CI, ADR validation done |

## Validation criteria

This ADR is validated when:

- [ ] `mimir-fhir /.well-known/smart-configuration` returns 200 with valid SMART 2.0 JSON
- [ ] Yggdrasil issues JWTs with `patient`, `encounter`, `fhirUser`, `scope`, `aud=mimir-fhir.{customer}` claims
- [ ] EHR launch from OpenEMR successfully loads asgard-cds app with patient context
- [ ] Standalone launch from asgard-portal.{customer} successfully loads asgard-eir-ui after Yggdrasil auth
- [ ] `patient/*.read` token correctly rejects requests for resources outside the bound patient
- [ ] `system/*.read` token via Backend Services (private_key_jwt) successfully calls bulk FHIR endpoints
- [ ] Refresh token exchange returns new access token within 5-min sliding window
- [ ] Token revocation propagates to all 5 surfaces (mimir-fhir REST, Hermodr MCP, CDS, Bifrost, eir-gateway) within ≤5 min
- [ ] Tyr receives `smart.token.*` events for issuance, refresh, revoke, expired-use
- [ ] At least one `smart.scope.denied` event fires from a privilege-violation test case
- [ ] CDS Hooks flow validates EHR-signed JWT separately from SMART access token
- [ ] Sprint 59 CDS pilot can be production-deployed via OpenEMR EHR launch path

## References

- [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md) — Single tenant Mac mini deployment
- [ADR-012](ADR-012-fhir-native-data-plane-no-ehr-replacement.md) — FHIR-native data plane (3-layer architecture)
- [ADR-013](ADR-013-fhir-r5-canonical-version.md) — R5 canonical version
- [ADR-014](ADR-014-fhir-data-plane-ownership.md) — Data plane ownership
- [ADR-016](ADR-016-asgard-fhir-profile-family.md) — Asgard FHIR Profile family
- [ADR-018](ADR-018-cds-cqm-as-eir-agent-family.md) — CDS + CQM as Eir agent families
- [ADR-019](ADR-019-fhir-profile-validation-tightest-binding-wins.md) — Profile validation
- [ADR-020](ADR-020-43files-hosxp-fhir-adapter.md) — 43Files adapter (Backend Services consumer)
- SMART App Launch 2.0 spec — https://hl7.org/fhir/smart-app-launch/
- SMART Backend Services — https://hl7.org/fhir/smart-app-launch/backend-services.html
- CDS Hooks 2.0 — https://cds-hooks.org/specification/current/
- OAuth2 (RFC 6749) — https://datatracker.ietf.org/doc/html/rfc6749
- PKCE (RFC 7636) — https://datatracker.ietf.org/doc/html/rfc7636
- JWT Profile for Client Authentication (RFC 7523) — https://datatracker.ietf.org/doc/html/rfc7523
- Asgard JWT auth pattern (internal) — Yggdrasil RS256 + `urn:zitadel:iam:org:id → tenant_id`
- Sprint 9 implementation — `crates/mimir-fhir/src/smart/` + `Yggdrasil/configs/smart-clients.yaml` + `Bifrost/src/smart/`
