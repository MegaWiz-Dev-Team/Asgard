# ADR-013: FHIR R5 as Canonical Version (Supersedes R4 Choice in ADR-006)

**Status:** Accepted
**Date:** 2026-05-23
**Deciders:** paripol@megawiz.co
**Scope:** Locks the FHIR specification version used as the canonical type system across `mimir-fhir`, `asgard-doc-pipeline-core`, all Layer 2 clinical modules, and all Hermodr MCP tool schemas. Supersedes the implicit R4 lock in [ADR-006](ADR-006-fhir-canonical-design.md) — the type design decisions in ADR-006 still apply, but the version is now R5.
**Supersedes (partial):** [ADR-006](ADR-006-fhir-canonical-design.md) — version-of-FHIR aspect only. Bundle.entry enum, audit-via-Tyr versioning, schemars, parsing strictness, and i18n decisions remain valid.
**Related:** [ADR-012 FHIR-native data plane](ADR-012-fhir-native-data-plane-no-ehr-replacement.md), [ADR-009 single-tenant Mac mini](ADR-009-single-tenant-mac-mini-deployment.md)

## Context

ADR-006 (2026-05-18) locked the canonical type system at FHIR **R4** without explicit version analysis — R4 was assumed as the default because it is the most widely deployed FHIR version globally.

On 2026-05-23, audit of the **MOPH-PC1 Data Element Mapping** (Thailand IG, Google Sheet `1n9FvDjd0Wnyx91g-X9UIFnFjLUUp3D6cLZH5OByGPh0`) revealed the spec maps elements to **FHIR R5**, not R4. Several element paths in the spec do not exist in R4 (e.g., `MedicationStatement.adherence`) or have different names (`Encounter.actualPeriod` vs R4 `period`; `Encounter.admission.dischargeDisposition` vs R4 `hospitalization.dischargeDisposition`). MOPH-PC1 conformance therefore requires R5.

Because Asgard has not yet implemented the type system (ADR-006 was a design lock, not a built artifact), the cost of switching from R4 to R5 is paper-only at this point. After Phase 1 implementation starts, refactoring would be expensive (every resource type, every adapter, every Hermodr tool schema).

This ADR locks the version **before** implementation begins.

## Decision

**FHIR R5 is the canonical version for the Asgard FHIR data plane.** All type definitions, REST endpoints, adapter targets, and tool schemas conform to R5. R4 is supported only at the **adapter boundary** (inbound translation from R4-emitting EHRs into R5 canonical).

### D1. Canonical = R5

`mimir-fhir` and `asgard-doc-pipeline-core` types follow FHIR R5 spec exactly. Resource paths, element names, cardinalities, value sets, and search parameters all use R5.

### D2. Adapter boundary translates R4 ↔ R5

Many existing EHRs (HAPI-FHIR-based, Medplum, older OpenEMR FHIR exports) emit R4. The `mimir-fhir` ingest adapter accepts R4 input and translates to R5 canonical at the boundary. Outbound, we emit R5 by default; R4 emission is available behind an explicit `?_format=fhir+json;fhirVersion=4.0` content negotiation header for clients that cannot consume R5.

Translation rules are codified in `mimir-fhir/src/translate/r4_to_r5.rs` (Rust module, table-driven where possible). Initial scope covers the 20 resources in our scope (post-ADR-006 Amendment 1) — see mapping table for element-level transforms.

### D3. Where R4 and R5 disagree on a field, R5 wins for storage

If a field changed shape between R4 and R5 (e.g., `MedicationRequest.medication` was `medicationCodeableConcept`/`medicationReference` polymorphism in R4 → single `CodeableReference` in R5), storage uses R5 shape. The R4 adapter folds both R4 variants into the R5 CodeableReference on ingest. On R4-emit, we synthesize whichever R4 variant fits.

### D4. R5-only fields are first-class

`MedicationStatement.adherence` (R5-new, ID 72 in MOPH-PC1) is supported natively. We do not synthesize an R4 equivalent on R4-emit; instead, we drop the field with an extension hint (`http://asgard.local/fhir/r5-only/medication-adherence`) so R5 clients can still consume it via extension semantics.

### D5. TH Core profile binding follows R5 baseline

[TH Core](https://fhir.moph.go.th) profiles are tracked at the R5 baseline. If MOPH later publishes R4-only profiles for legacy hospital interoperability, those are honored at the R4 emission path only — the R5 canonical store does not regress.

## Why R5 over R4

| Factor | R4 | R5 | Verdict |
|---|---|---|---|
| **MOPH-PC1 conformance** | requires translation gap; `MedicationStatement.adherence` unmappable | direct fit | R5 wins |
| **Thai MOH IG direction** | current published IG is R4-ish but MOPH-PC1 spec is R5 | aligned with active spec direction | R5 wins |
| **R5-specific clinical fields** | missing `MedicationStatement.adherence`, `Encounter.admission.*` refactor, `Encounter.actualPeriod` | first-class | R5 wins |
| **Ecosystem maturity (libraries)** | broader (HAPI, Medplum, fhir.js, fhirclient.js) | narrower but growing | R4 wins, marginal |
| **Rust crate support** | `fhir-rs`, `fhir-sdk-rs` mostly target R4 | partial R5 support, will need contributions | R4 wins, marginal |
| **Existing EHR FHIR exports** | most R4 (HAPI-backed) | rare R5 native | R4 wins, mitigated by adapter |
| **Cost of refactor later** | low now (paper lock) | impossible after Phase 1 ships | R5 wins on irreversibility |
| **Distance from spec drift** | R4 is frozen 2019; R5 published 2023 | active spec; R6 announced for 2026+ | tie |

The four R5 wins (conformance, alignment, R5-specific fields, irreversibility) outweigh the two marginal R4 wins (library breadth) — especially given we are Rust-first and will write our own type system regardless of crate ecosystem.

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Dual-support R4 + R5 in the canonical store | Doubles type definitions, audit shapes, validators; we already have storage-layer complexity from MariaDB + Neo4j. The adapter boundary is enough. |
| Wait for FHIR R6 | R6 stable target is 2026+ ballot, GA likely 2027+. We cannot delay Phase 1 that long. R5 is the right "current" target. |
| Stay R4 and translate spec R5 → R4 internally | Loses `MedicationStatement.adherence` (mappable only via extension); reverses the direction of spec drift (we would drift away from MOPH-PC1, not toward it). |
| Use FHIR R4B as a middle ground | R4B was a maintenance branch with limited adoption. Picking it adds confusion without solving the R5-only-fields problem. |

## Consequences

**Positive:**

- Direct conformance to MOPH-PC1 spec — no translation gap in the canonical store
- Forward-compatible with Thai MOH IG direction
- R5-only clinical fields (e.g., adherence) are first-class, not bolted on
- Cost of lock is paper-only because Phase 1 implementation has not started

**Negative:**

- Rust FHIR crate ecosystem is R4-leaning; we will write more R5 types from scratch (`schemars` + manual cardinality annotations per ADR-006 Decision 3)
- Adapter complexity: every R4-emitting EHR (most of them) requires R4→R5 translation on ingest
- R5 clients are rare today; on-the-wire compatibility with most external systems requires R4 emission path (added but kept narrow)

**Neutral / TBD:**

- Whether to pin to a specific R5 minor version (5.0.0 vs latest) for hash-stable validators — defer to Phase 1 detail design
- TH Core profile versioning: MOPH publishes profile updates without bumping the base FHIR version — we track profile versions independently of FHIR base version

## Impact on ADR-006

ADR-006 Decisions 1-5 remain valid (Bundle.entry closed enum, audit-via-Tyr versioning, schemars JSON Schema, hybrid parsing strictness, i18n via `_language` extension). Only the implicit assumption that "R4 is the version" is changed. ADR-006 Status moves to "Accepted (amended 2026-05-23 — see Amendment 1)" and the resource scope changes from 15 → 20 (see ADR-006 Amendment 1, applied in parallel with this ADR).

The 15 resources listed in ADR-006 Decision 1's `BundleEntry` enum are re-typed in R5 shape. The enum structure stays; the field shapes inside each variant change. Translation is mechanical for ~14 of 15 (small field renames). `MedicationRequest.medication` changes shape materially (CodeableReference); `Encounter` requires the `hospitalization` → `admission` refactor; `MedicationStatement` gains `adherence`.

## Validation criteria

This ADR is validated when:

- [ ] `mimir-fhir` Rust crate compiles with R5 type definitions for the 20-resource scope
- [ ] Round-trip test: R5 Bundle → JSON → R5 Bundle is identity for the MOPH-PC1 test corpus
- [ ] Round-trip test: R4 Bundle → R5 canonical → R4 Bundle is identity for the lossless subset (loses R5-only fields, documented)
- [ ] `MedicationStatement.adherence` ingest from R5 source preserves the field; R4 emission drops it with extension annotation
- [ ] At least one R4-emitting test EHR (e.g., HAPI sandbox or OpenEMR FHIR) parses end-to-end via the R4→R5 adapter

## References

- ADR-006: FHIR R4 canonical design (now amended; this ADR supersedes the version aspect)
- ADR-012: FHIR-native data plane strategic decision
- MOPH-PC1 Data Element Mapping — `docs/architecture/moph_pc1_fhir_mapping.md`
- FHIR R5 spec — http://hl7.org/fhir/R5/
- FHIR R4 spec (for adapter reference) — http://hl7.org/fhir/R4/
- FHIR Thailand IG — https://fhir.moph.go.th
- R4-R5 diff — http://hl7.org/fhir/R5/diff.html