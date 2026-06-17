# ADR-015: Expand mimir-fhir Scope to 21 Resources (Add Composition) + Insert UC2 Patient Summary

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Adds `Composition` (R5) as the 21st canonical resource in `mimir-fhir`. Inserts a new use case **UC2 — Cross-Encounter Patient Summary** into Sprint 10 demo set alongside UC1 (OPD HT/DM) and UC3 (paediatric immunization). Amends [ADR-006](ADR-006-fhir-canonical-design.md) Decision 1 (Bundle.entry enum) — see Amendment 2 inline in ADR-006.
**Related:** [ADR-006](ADR-006-fhir-canonical-design.md) Amendment 2 (Bundle.entry enum +1), [ADR-013 R5 canonical](ADR-013-fhir-r5-canonical-version.md), [ADR-014 data plane ownership](ADR-014-fhir-data-plane-ownership.md)

## Context

The `mimir-fhir` Phase 1 scope was locked at 20 resources, bounded by the MOPH-PC1 78-element mapping (per [ADR-006 Amendment 1](ADR-006-fhir-canonical-design.md), 2026-05-23). MOPH-PC1 does not require `Composition` because the spec is data-element-level, not document-level — every PC1 element maps to a leaf resource (Observation, Condition, MedicationStatement, etc.).

However, a clinical use case has emerged that the 20-resource scope cannot serve cleanly:

> A clinician opens a patient's record (often after referral or first encounter at a new clinic) and wants a **single structured summary** of "what is going on with this patient" — active problems, current medications, known allergies, recent vitals and labs, ongoing care plan — built from data across many prior encounters.

This is the classic FHIR **`Composition`** resource use case. It is also exactly the structure that the International Patient Summary (IPS) IG and the upcoming MOPH discharge summary spec target.

Sprint 9 (Smart-on-FHIR Launch, line 431 of phase-1-plan.md) already mentions rendering "a simple patient summary view" but only as **UI markup**, not as a persisted FHIR resource. Without a `Composition`:

- the summary cannot be re-emitted to an external EHR or another Asgard module
- there is no auditable record (via Tyr) of what summary the clinician saw at decision time
- downstream Layer 2 modules (eir-ddx, med-reconciliation, discharge-summary) cannot consume "the summary" as an input — they must re-aggregate from leaf resources every time
- there is no clean home for the LLM-generated narrative (`Composition.section.text.div`)

Two alternatives were considered and rejected:

**Alt 1 — Use `DocumentReference` (in current 20)** to wrap a Markdown summary. Rejected because `DocumentReference` is a blob pointer + metadata; it cannot reference individual `Condition` / `Observation` resources inside its sections, so consumers lose structural navigation. SMART-on-FHIR apps would have to parse our Markdown to extract problems.

**Alt 2 — Defer Composition until Phase 2.** Rejected because the eir-summary clinical module (Layer 2) is the highest-leverage early demo for clinician audiences (per [[med_open_claw_initiative]]) and gating it on a Phase 2 spec adds 6+ months. Cost of adding Composition to Phase 1 is one Sprint 4 task + one Sprint 10 demo + one profile in Sprint 7.

## Decision

### D1. Add `Composition` as the 21st canonical resource

`mimir-fhir/src/resources/composition.rs` ships in Sprint 4 alongside the existing 7 clinical resources (Condition, MedicationRequest, MedicationStatement, Procedure, AllergyIntolerance, DiagnosticReport, DocumentReference). [ADR-006](ADR-006-fhir-canonical-design.md) Decision 1 (`BundleEntry` closed enum) is amended (Amendment 2) to include the new variant.

### D2. R5 baseline + Asgard-specific profile

Type definition follows FHIR R5 spec exactly. An Asgard-specific profile `Composition-asgard-patient-summary` constrains the resource for the UC2 use case:

- `type` = LOINC `60591-5` ("Patient summary Document")
- `status` = `preliminary` (LLM-drafted) or `final` (clinician-attested)
- `subject` required → `Patient`
- `author` required → `Practitioner` OR `Device` (when LLM-authored without human attestation, `author = Device(asgard-eir-summary-v{N})`)
- `section` required, with the 6-section structure defined in [composition-uc2-patient-summary-spec.md](../technical/composition-uc2-patient-summary-spec.md)

The profile is **inspired by but not strictly conformant to** the IPS (International Patient Summary) IG. IPS R5 is still draft as of 2026-05; pinning to a draft IG creates churn. The Asgard profile uses the same 3 IPS "required" sections (Problems, Medications, Allergies) and 3 IPS "recommended" sections (Results, Vital signs, Plan of care) so a future migration to strict IPS conformance is mechanical.

### D3. R4↔R5 translator: identity transform

Composition has **no breaking changes** between R4 and R5 that affect the fields used in UC2 (`type`, `status`, `subject`, `date`, `author`, `title`, `section`). The R4↔R5 translator entry for Composition is an identity transform with version-tag updates only. Confirmed against the FHIR R4/R5 diff index.

### D4. Insert UC2 into Sprint 10 demo set

Sprint 10 demo set becomes UC1 + UC2 + UC3. UC2 demo scope:

- Seed 3 demonstration patients with multi-encounter histories (1 simple, 1 chronic-complex, 1 polypharmacy)
- `eir-summary` agent (DB row in `agent_configs`, model `gemma-4-26b` per [[feedback_eir_agents_local_only]]) generates `Composition` JSON for each
- `Composition` validates against `Composition-asgard-patient-summary` profile (Sprint 7 validator)
- Smart-on-FHIR app renders the Composition with per-section navigation
- Tyr audit chain records the LLM author, model version, input resource set, and output hash

### D5. Sprint 4 task list update

Sprint 4 adds one task:

- [ ] **Composition** (R5) — Asgard profile-aware
  - `type`, `status`, `subject`, `date`, `author` (Practitioner OR Device), `title`, `section[]`
  - `section.text.div` (XHTML narrative), `section.entry[]` (references to Condition/MedicationStatement/AllergyIntolerance/Observation in same Bundle)
  - Helper: `Composition::asgard_patient_summary(subject, author, sections)` builder

Sprint 4 budget shifts from ~10 days to ~11 days (one extra day for type + translator stub).

### D6. Sprint 7 profile validator addition

Sprint 7 adds `Composition-asgard-patient-summary` profile validation to the tightest-binding-wins validator chain. No new dependency; same validator infrastructure.

### D7. Sprint 9 patient-summary UI binds to Composition

Sprint 9 task list updates from "renders simple patient summary view" to "renders `Composition` resource with per-section navigation." This is a *clarification*, not a scope expansion — the UI was already planned.

## Why Composition over DocumentReference (revisited)

| Factor | DocumentReference | Composition | Verdict |
|---|---|---|---|
| Already in 20-resource scope | yes | no (this ADR adds) | DocRef wins |
| Section-level structure | no (blob + metadata) | yes (typed sections with entry refs) | Composition wins |
| Per-section entry references to Condition/Observation/etc. | no | yes | Composition wins |
| SMART-on-FHIR navigation | requires parsing Markdown | structural | Composition wins |
| LLM narrative attribution | via `author` extension hack | first-class `author = Device` | Composition wins |
| Tyr audit semantics | "document hash X attached" | "summary of resources A,B,C generated by author D" | Composition wins |
| Cost to add | 0 | ~1 sprint-day + profile + UI update | DocRef wins |

The structural and semantic wins outweigh the marginal scope-creep cost.

## Why not full IPS profile conformance

| Factor | Asgard profile | Strict IPS R5 | Verdict |
|---|---|---|---|
| Spec stability | Asgard-controlled, versioned | IPS R5 is draft (2026) | Asgard wins |
| Section count | 6 (3 required + 3 recommended) | 3 required + ~14 optional | Asgard wins on focus |
| SNOMED CT terminology binding | optional in Phase 1 (TMT/ICD-10-TM primary) | mandatory | Asgard wins (no SNOMED license blocking) |
| Future migration path | structural compatibility maintained | trivial — add `meta.profile` + tighten value sets | tie |
| Marketing / interop story | "Asgard-flavoured" | "IPS-conformant" | IPS marginally better |

Locking to draft IPS R5 now creates rework when IPS R5 ballots. Asgard profile maintains structural compatibility for cheap upgrade once IPS R5 is normative.

## Consequences

**Positive**

- UC2 patient summary use case becomes Phase 1 deliverable (alongside UC1 + UC3)
- Layer 2 modules (eir-ddx, med-reconciliation, discharge-summary) get a structured input type for free
- Tyr audit chain gets first-class "summary-generated" event semantics
- IPS-conformance migration is structurally cheap (post-Phase 1)

**Negative**

- Sprint 4 budget +1 day (~10 → ~11 days)
- Sprint 7 profile validator adds 1 profile (~half day)
- Sprint 9 UI scope clarified (no net extra effort, but UI bound to Composition shape)
- Sprint 10 demo +1 demo (~2 days net for UC2 demo prep)
- `BundleEntry` enum +1 variant — touch every match site
- 21 resources slightly weakens the "bounded by PC1" narrative; mitigated by the explicit "+1 for clinical document support" justification in ADR-006 Amendment 2

**Neutral**

- No R4↔R5 translation complexity (identity transform)
- No new code system bindings required (uses existing LOINC + ICD-10-TM + TMT)

## Open questions

1. **Author attribution model for LLM-generated summaries.** Should `author` be `Device(asgard-eir-summary)` or `Practitioner` (the clinician who reviewed) or both (`author[]` with both)? Recommended: `author[Device, Practitioner]` once clinician attests; `author[Device]` only when status=`preliminary`. Decided in design spec, not in this ADR.

2. **Versioning of generated summaries.** Patient state changes daily — should we re-generate Composition every fetch, or persist + invalidate? Recommended: regenerate on-demand for `status=preliminary`; persist only on clinician attestation (`status=final`). Tyr captures both paths.

3. **Confidentiality classification.** Per MOPH PDPA, patient summaries containing mental health / HIV / pregnancy history have tighter access controls. Phase 1: respect `Composition.confidentiality` field but enforcement is Phase 2. Sprint 10 demo uses non-sensitive demo data.

## Links

- [ADR-006 Amendment 2](ADR-006-fhir-canonical-design.md) — Bundle.entry +1
- [ADR-013 R5 canonical](ADR-013-fhir-r5-canonical-version.md)
- [ADR-014 data plane ownership](ADR-014-fhir-data-plane-ownership.md)
- [composition-uc2-patient-summary-spec.md](../technical/composition-uc2-patient-summary-spec.md) — design detail (schema + sections + preamble)
- [mimir-fhir-phase-1-plan.md](../technical/mimir-fhir-phase-1-plan.md) — Sprint 4 + 10 scope amendments
- [[feedback_eir_agents_local_only]] — eir-summary must use gemma-4-26b / medgemma / typhoon (no cloud LLM)
- [[asgard_agent_registry]] — eir-summary as DB row pattern