# ADR-014: FHIR Data Plane Lives in Mimir; Eir Consumes via REST/Crate

**Status:** Accepted
**Date:** 2026-05-24
**Deciders:** paripol@megawiz.co
**Scope:** Resolves the ownership question for the FHIR data plane (canonical FHIR R5 store, REST endpoint, adapters, profile validators, R4↔R5 translator). Locks the boundary between Mimir family (data plane) and Eir family (clinical apps consuming the data plane).
**Related:** [ADR-006 FHIR canonical design](ADR-006-fhir-canonical-design.md), [ADR-009 single-tenant Mac mini](ADR-009-single-tenant-mac-mini-deployment.md), [ADR-010 agents as boundaries, skills as expertise](ADR-010-agents-as-boundaries-skills-as-expertise.md), [ADR-012 FHIR-native data plane](ADR-012-fhir-native-data-plane-no-ehr-replacement.md), [ADR-013 FHIR R5 canonical version](ADR-013-fhir-r5-canonical-version.md)

## Context

`mimir-fhir` was placed inside the Mimir family (at `Mimir/ro-ai-bridge/mimir-fhir/`) during the ADR-012 drafting on 2026-05-23, following the existing Mimir submodule naming convention (`mimir-rag`, `mimir-well`, `mimir-curator`). This placement was made implicitly — never formally validated against the alternative of putting FHIR ownership in the Eir family.

On 2026-05-24, after Sprint 1 Days 1-5 of scaffolding work landed (133 tests across 11 datatypes, all green, fully additive to `mimir-fhir/`), the ownership question was raised explicitly: should the FHIR data plane belong to Mimir or to Eir?

This ADR closes that question.

## Decision

**The FHIR data plane lives in the Mimir family** as `mimir-fhir` (and any future siblings like `mimir-fhir-adapters` if the crate splits). Eir family modules consume FHIR resources via REST (Smart-on-FHIR launch) or compile-time Rust crate dependency. Eir modules MUST NOT own FHIR storage, MUST NOT bypass `mimir-fhir` profile validation, and MUST NOT duplicate FHIR type definitions.

### D1. Mimir family owns Layer 1

| Concern | Owner | Where |
|---|---|---|
| FHIR R5 type system (20 resources, datatypes) | Mimir | `Mimir/ro-ai-bridge/mimir-fhir/src/datatypes/`, `src/resources/` |
| REST endpoint (`/fhir/r5/{ResourceType}/...`) | Mimir | `mimir-fhir/src/rest/` (Sprint 6+) |
| R4↔R5 translator | Mimir | `mimir-fhir/src/translate/r4_to_r5/` |
| 43Files-to-FHIR adapter | Mimir | `mimir-fhir/src/adapters/forty_three_files/` |
| OpenEMR ↔ FHIR adapter | Mimir | `mimir-fhir/src/adapters/openemr/` (Sprint 8+) |
| HL7 v2 → FHIR adapter (lab) | Mimir | `mimir-fhir/src/adapters/hl7v2/` (Phase 3) |
| TH Core + MoPH-PC profile validators | Mimir | `mimir-fhir/src/profiles/`, `src/validators/` |
| FHIR resource persistence (MariaDB) | Mimir | `mimir-fhir/src/persistence/` (Sprint 6+) |
| Tyr audit integration for FHIR writes | Mimir (via existing audit pattern) | `mimir-fhir/src/persistence/audit.rs` |

### D2. Eir family owns Layer 2 (clinical apps)

| Module | Where | Purpose |
|---|---|---|
| `eir-ddx` | `Eir/eir-ddx/` (Phase 2) | Differential diagnosis Smart-on-FHIR app |
| `eir-care-pathway` | `Eir/eir-care-pathway/` (Phase 3) | FHIR PlanDefinition / ActivityDefinition executor (STEMI bundle, sepsis bundle, etc.) |
| `eir-mar` | `Eir/eir-mar/` (Phase 3) | Medication administration record |
| `eir-acls` | `Eir/eir-acls/` (Phase 3) | Code Blue timer + drug dosing |
| `eir-or-checklist` | `Eir/eir-or-checklist/` (Phase 3) | WHO Surgical Safety Checklist |
| `eir-vaccine-schedule` | `Eir/eir-vaccine-schedule/` (Phase 2) | Thai EPI schedule logic over Immunization resource |
| `eir-med-reconciliation` | `Eir/eir-med-reconciliation/` (Phase 3) | Discharge medication reconciliation |
| `eir-sbar-handoff` | `Eir/eir-sbar-handoff/` (Phase 4) | Nursing SBAR generator |

Existing Eir specialty agents (`eir`, `eir-cardio`, `eir-sleep`, `eir-ent`, `eir-pediatrics`, `eir-router`) continue to live in their current location. They consume FHIR resources via `mimir-fhir` REST API.

### D3. Contract — what Eir modules MAY and MUST NOT do

**Eir Layer 2 modules MAY:**
- Read FHIR resources from `mimir-fhir` via REST (`GET /fhir/r5/{ResourceType}/{id}`)
- Take a compile-time Rust dependency on `mimir-fhir` crate for type-safe Resource handling
- Produce derived clinical-decision output (rendered UI, suggestions, alerts) that REFERENCES FHIR resource IDs
- Launch as Smart-on-FHIR apps from a host EHR
- Emit MCP tool calls through Hermodr that resolve to `mimir-fhir` REST under the hood

**Eir Layer 2 modules MUST NOT:**
- Persist FHIR resources in their own database
- Skip TH Core / MoPH-PC profile validation
- Define their own copies of FHIR resource types
- Implement their own FHIR REST endpoints
- Embed a R4↔R5 translator (call `mimir-fhir`'s)
- Connect directly to legacy hospital DBs (HOSxP, OpenEMR) — go through `mimir-fhir` adapters

### D4. Naming alignment

Per [[feedback_no_new_norse_components]] the established submodule pattern is `<parent>-<submodule>`. Mimir family currently has `mimir-rag`, `mimir-well`, `mimir-curator`. Adding `mimir-fhir` follows this pattern. Future Mimir-side splits (if `mimir-fhir` outgrows itself) follow the same: `mimir-fhir-core`, `mimir-fhir-adapters`, `mimir-fhir-rest`.

Eir Layer 2 modules use the parallel pattern: `eir-ddx`, `eir-care-pathway`, etc. They are siblings of the existing specialty agents (`eir-cardio`, `eir-sleep`, etc.), not children of them.

## Why Mimir over Eir

The vote weighed both options across 11 dimensions; Mimir won 9, Eir won 2. The decisive factors:

1. **Single shared store across 19 Eir variants** — placing FHIR storage inside any one Eir agent forces the others into either duplication or cross-agent calls. Mimir is the natural single-owner.
2. **Data persistence is Mimir's existing scope** — MariaDB schemas (ICD-10 cascade, SNOMED), Neo4j (PrimeKG, mimir-well), Qdrant (embeddings) all live in Mimir already. Adding FHIR tables is incremental, not architecturally new.
3. **Adapters fit Mimir's ingest pattern** — 43Files-to-FHIR is analogous to the existing ICD-10 / SNOMED / TMT ingest jobs already in Mimir. Eir does not have an ingest pattern.
4. **Compute profile separation** — Eir = LOCAL LLM (RAM-hungry MLX/ANE per [[mac_mini_specs]]). Mimir = data + retrieval (CPU/disk). Co-locating FHIR with LLM in Eir creates resource contention on the Mac mini 64GB ceiling.
5. **REST endpoint** — `mimir-api` already serves :8090. Adding `/fhir/r5/...` is incremental. `eir-gateway` exists but its scope is agent invocation, not data plane.
6. **Tenant scope** — Mimir is tenant-agnostic infrastructure (asgard_medical, asgard_insurance, asgard_wellness, asgard_platform all use the same Mimir). Eir is tenant-clinical (`asgard_medical` only). FHIR data plane fits the tenant-agnostic shape.
7. **Mimir Guideline Lineage joins Patient/Encounter** — Living Evidence joins guidelines with patient context. Co-locating both in Mimir means queries stay in-process; cross-component calls would add latency + complexity.
8. **ADR/code momentum** — ADR-006/012/013 already say `mimir-fhir`; the Rust crate scaffolded over 5 days has 133 tests; blog post 33 references `mimir-fhir`. Moving now = paper churn for no architectural win.

The Eir-favoring arguments:
- "FHIR Patient is operational EHR data, not knowledge" — valid in 2024, but Mimir's scope has evolved (mimir-well = memory artifacts; mimir-curator = annotation; mimir-fhir = canonical data plane). Mimir is no longer "RAG only".
- "Eir is clinician-facing" — true, but only for the UX layer. Storage + REST + adapter are infrastructure, separable. Eir Layer 2 modules being clinician-facing is preserved under D2.

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Move `mimir-fhir/` to `Eir/` directory | Forces duplication or cross-agent ownership; refactors 24 files + 133 tests + 3 ADRs + blog post 33 for zero architectural gain |
| Split out as standalone `asgard-fhir` (new Norse component) | Violates [[feedback_no_new_norse_components]] (5 active families is enough); no on-prem use case demands FHIR-only mini box yet |
| Allow Eir modules to write FHIR directly when "convenient" | Creates two writers → write-amplification + audit-trail fragmentation + profile-validation-skip risk |
| Allow Eir modules to maintain "local cached copies" of FHIR resources | Cache invalidation problem; mimir-fhir should serve reads (with its own cache if needed) |

## Consequences

**Positive:**
- Single source of truth for FHIR storage + validation
- 19 Eir agents share one canonical FHIR API; no per-agent rework when FHIR types evolve
- Compute resource discipline preserved (LLM in Eir, data in Mimir, no contention)
- Existing ADR/code work is preserved as-is — zero refactor cost
- Clear contract enables independent evolution of Mimir-side data plane and Eir-side clinical apps

**Negative:**
- Inter-component call required when Eir reads FHIR (mitigated: REST is fast, mimir-api co-located in same K8s cluster)
- Two component teams must coordinate when FHIR types evolve (mitigated: mimir-fhir is a published crate; semver discipline per [[semver_release_process]])
- "Mimir" semantic stretch — name evokes "memory/knowledge", but scope is now "data plane". Future renaming TBD.

**Neutral / TBD:**
- If a customer ever buys FHIR-only deployment (no Eir, no Bifrost, no Heimdall), we revisit standalone `asgard-fhir`. Not currently in roadmap.
- If `mimir-fhir` crate grows past ~50K LOC or 50 resources, split into `mimir-fhir-core` + `mimir-fhir-rest` + `mimir-fhir-adapters` within Mimir family. ADR amendment, not new component family.

## Open questions

1. **Hermodr MCP tool ownership for FHIR** — should `mimir-fhir` ship Hermodr MCP tool definitions itself, or does Hermodr own them and call `mimir-fhir` REST? Defer to Phase 1 detail design.
2. **Eir consumption pattern** — REST for cross-pod calls, or compile-time crate import for same-pod / co-located Eir modules? Likely both, depending on deployment shape. Defer to Phase 2 first Eir Layer 2 module (eir-ddx).
3. **Smart-on-FHIR launcher** — does `mimir-fhir/src/rest/smart_launch.rs` own the OAuth2 launch flow, or does Yggdrasil (Asgard's auth layer per [[asgard_jwt_auth_pattern]])? Likely Yggdrasil for OAuth2 + mimir-fhir for SMART configuration endpoint. Defer to Phase 1 Sprint 9.

## Validation criteria

This ADR is validated when:

- [ ] No Eir module persists FHIR resources outside `mimir-fhir`
- [ ] No Eir module duplicates FHIR resource types (CI lint can catch this — search for `struct Patient`, `struct Encounter`, etc. outside `mimir-fhir`)
- [ ] At least one Eir Layer 2 module (eir-ddx Phase 2) consumes `mimir-fhir` end-to-end via REST
- [ ] Phase 1 demo (UC1 OPD HT/DM) runs Eir specialty agents reading FHIR from `mimir-fhir`, not from a private store

## References

- ADR-006: FHIR canonical type system
- ADR-009: single-tenant Mac mini deployment
- ADR-010: agents as boundaries, skills as expertise
- ADR-012: FHIR-native data plane (3-layer architecture)
- ADR-013: FHIR R5 canonical version
- [`feedback_no_new_norse_components`](../../../.claude/projects/-Users-mimir-Developer/memory/feedback_no_new_norse_components.md) — Mimir family submodule pattern
- [`asgard_components_roles`](../../../.claude/projects/-Users-mimir-Developer/memory/asgard_components_roles.md) — Mimir = RAG, Eir = clinical agent
