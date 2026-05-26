# ADR-017: FHIR R4↔R5 Translation Framework

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Defines the framework for implementing R4↔R5 field-level translation in `mimir-fhir::translate::*` — categories, severity levels, audit hooks, extension namespace, and test corpus. Operationalizes [ADR-013](ADR-013-fhir-r5-canonical-version.md) Decision D2 ("Adapter boundary translates R4↔R5") and Decision D4 ("R5-only fields are first-class").
**Related:** [ADR-006](ADR-006-fhir-canonical-design.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-016](ADR-016-asgard-fhir-profile-family.md)

## Context

ADR-013 locked FHIR R5 as the canonical version and committed to a translation layer at the adapter boundary — `mimir-fhir::translate::r4_to_r5` and reverse — without specifying the framework. Sprint 2 (Patient + Encounter + R4↔R5 translator scaffold) is the next sprint and must commit to a concrete framework before any per-resource implementation begins.

Per-field translation between R4 and R5 spans four distinct shapes of change:

1. **Identical fields** (most primitives, addresses) — pass-through.
2. **Renamed / restructured fields** — `Encounter.period` → `Encounter.actualPeriod`; `Encounter.hospitalization.*` → `Encounter.admission.*`.
3. **Type-system upgrades** — R4 `medication[x]` Choice (CodeableConcept | Reference) → R5 `medication` CodeableReference; cardinality promotion 0..1 → 0..*.
4. **R4-only or R5-only fields** — `Encounter.statusHistory` was deprecated in R5; `MedicationStatement.adherence` is R5-new.

Without a typed framework the translation layer becomes a sprawl of ad-hoc functions with no audit trail, no consistent lossy-handling policy, and no roundtrip test discipline. After Sprint 2 implementation begins, retrofitting the framework would force rewrites of every per-resource module.

## Decision

Adopt an 8-category × 4-severity translation framework with mandatory audit emission and a golden-corpus roundtrip test discipline.

### D1. Eight field-mapping categories

Every field mapping in the R4↔R5 translator is tagged with exactly one category:

| # | Category | Symbol | Example |
|---|---|---|---|
| 1 | Identical | `≡` | `Patient.gender` |
| 2 | Renamed | `→` | `Encounter.period` → `Encounter.actualPeriod` |
| 3 | Restructured | `↻` | `Encounter.hospitalization` → `Encounter.admission` |
| 4 | Cardinality-promoted | `1↑*` | `Encounter.class` (Coding 0..1) → (CodeableConcept 0..*) |
| 5 | Type-upgraded | `⤴` | `MedicationRequest.medication[x]` → `medication` (CodeableReference) |
| 6 | R5-only NEW | `+5` | `MedicationStatement.adherence` |
| 7 | R4-removed | `−5` | `Encounter.statusHistory` (deprecated in R5) |
| 8 | Vocabulary re-bind | `≈` | `MedicationStatement.status` enum vocabulary changed |

Categories drive how the translator validates, audits, and tests each field. A field cannot be implemented without a category tag.

### D2. Four lossy-rule severity levels

Each category instance carries one of four rule types:

```rust
pub enum LossyRule {
    /// Bit-exact roundtrip. R4 ↔ R5 preserves data perfectly.
    Lossless,

    /// Roundtrip preserves via Asgard extension. R5→R4 emits an
    /// extension carrying the R5-only or R4-removed value;
    /// R4→R5 reads the extension back if present.
    LossyWithExtension { url: &'static str },

    /// Forward translation computes a best-effort value from
    /// available source data. Named function for auditability.
    LossyDerive { derivation_fn: &'static str },

    /// Data is dropped. Must include a static reason string
    /// and a reference to the ADR section justifying the drop.
    LossyDrop { reason: &'static str },
}
```

`LossyDrop` requires an ADR sub-section justifying every drop. Silent loss is prohibited.

### D3. Translation result carries warnings

Translators return a result envelope, not a bare value:

```rust
pub struct TranslationResult<T> {
    pub value: T,
    pub warnings: Vec<TranslationWarning>,
    pub extensions_added: Vec<ExtensionUrl>,
}

pub struct TranslationWarning {
    pub resource_type: &'static str,
    pub field_path: &'static str,
    pub category: TranslationCategory,
    pub rule: LossyRule,
    pub source_value: Option<serde_json::Value>,
    pub direction: Direction, // R4ToR5 | R5ToR4
}
```

Every warning is emitted to the audit sink as a structured event (see D6).

### D4. Bidirectional traits

`mimir-fhir` defines two traits in `translate/mod.rs`:

```rust
pub trait R4ToR5 {
    type R4Input;
    type R5Output;
    fn translate(input: Self::R4Input) -> TranslationResult<Self::R5Output>;
}

pub trait R5ToR4 {
    type R5Input;
    type R4Output;
    fn translate(input: Self::R5Input) -> TranslationResult<Self::R4Output>;
}
```

Both directions are implemented in Sprint 2 for Patient and Encounter. Per-resource files live at `mimir-fhir/src/translate/{resource}.rs`.

R5→R4 is needed because [ADR-013](ADR-013-fhir-r5-canonical-version.md) Decision D2 permits R4 emission for clients negotiating `fhirVersion=4.0`. Sprint 9 (Smart-on-FHIR) consumes the reverse path; Sprint 2 ships it together to lock the framework symmetrically.

### D5. Lossy-with-Extension namespace

R4↔R5 round-trip preservation uses extensions under a single namespace owned by Asgard:

```
http://asgard.megawiz.co.th/fhir/extension/r4r5/{Resource}.{path}
```

Examples:
```
http://asgard.megawiz.co.th/fhir/extension/r4r5/Encounter.statusHistory
http://asgard.megawiz.co.th/fhir/extension/r4r5/Encounter.classHistory
http://asgard.megawiz.co.th/fhir/extension/r4r5/Encounter.diagnosis.rank
```

The namespace lives under `asgard.megawiz.co.th` (Megawiz's owned public domain) so that extensions are de-referenceable when the registry page is published. The registry document is `docs/architecture/fhir-r4r5-extensions.md` (to be created in Sprint 2 Day 8), which serves as both internal reference and open-source contribution to the Thai FHIR community.

ADR-013's earlier reference to `http://asgard.local/fhir/r5-only/...` (R5-only field hint on R4-emit) is hereby unified with this namespace. ADR-013's `asgard.local` URLs are reclassified as drafts; the canonical namespace for all Asgard FHIR extensions is `asgard.megawiz.co.th`. ADR-013 receives a textual amendment but no decision change.

### D6. Audit emission via Tyr

Every `TranslationWarning` becomes a Tyr Wazuh event:

```
event_type:   fhir.translation.warning
fields:
  direction:       "R4ToR5" | "R5ToR4"
  resource_type:   "Encounter" | ...
  field_path:      "Encounter.statusHistory"
  category:        "−5" (R4-removed)
  rule:            "LossyWithExtension"
  extension_url:   "...statusHistory" (when applicable)
  patient_hash:    sha256(citizen_id) (when applicable, via Skuggi)
  source_request:  trace_id from heimdall-trace
```

Tyr aggregates these into a daily data-quality report. Customers see "your R4 EHR is emitting 12% of Encounters without `period.end` — translation must derive from `length`" without exposing PHI.

### D7. Golden corpus mandatory

Every resource translator ships with three test tiers:

| Tier | Test | Pass criteria |
|---|---|---|
| 1 | R4 lossless roundtrip (R4 → R5 → R4) | bit-exact |
| 2 | R5-only roundtrip (R5 → R4 with extensions → R5) | bit-exact via extension stash |
| 3 | Lossy-derive forward (R4 → R5) | snapshot match + expected warnings list |

Corpus generation: synthetic property-based + Thai Faker (the pattern adopted from prior AWS QuickSuite analysis) — no real patient data. Target: 50 cases per resource by Sprint 2 end (Patient + Encounter), additional 50 per resource as each subsequent resource lands.

Location: `crates/mimir-fhir/tests/golden/{resource}/{tier}/case_NNN.{r4,r5,warnings}.json`.

### D8. Implementation guard: macro-based field registration

To prevent silent omission of fields, each translator declares its field map via a macro that exhaustively cross-checks against the generated R4 and R5 type definitions at compile time:

```rust
translation_map! {
    resource: Encounter,
    fields: {
        "identifier" => Identical(Lossless),
        "status" => VocabularyRebind(LossyDerive { derivation_fn: "encounter_status_r4_to_r5" }),
        "statusHistory" => R4Removed(LossyWithExtension {
            url: "http://asgard.megawiz.co.th/fhir/extension/r4r5/Encounter.statusHistory"
        }),
        "class" => CardinalityPromoted(LossyDerive { derivation_fn: "wrap_coding_in_cc_array" }),
        // ... every R4 and R5 field must appear
    }
}
```

Missing fields cause compile error; unknown fields cause compile error. This is the architectural guard against silent drift between FHIR spec evolution and translator coverage.

## Why this framework over alternatives

| Alternative | Reason rejected |
|---|---|
| Free-form per-resource Rust functions | No audit trail, no consistent lossy policy, no compile-time exhaustiveness check |
| JSON-path-based table-driven translator (like fhir-converter) | String-based paths drift silently when FHIR types regenerate; no compile-time guarantee |
| FHIR ConceptMap resources for the rules | Resource-level CM works for terminology, not for structural reshape; overkill for our 20-resource scope |
| Defer R5→R4 until Sprint 9 (Smart-on-FHIR) | Framework symmetry is cheapest to establish in Sprint 2; deferral risks asymmetric API design |
| Single severity (lossy/lossless boolean) | Loses the audit nuance — "lossy with extension" and "lossy drop" have very different regulatory implications |

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Auto-generate translator from FHIR diff spec | The HL7 R4-R5 diff page is not machine-readable for our needs; manual codification with macro guard is cheaper and more reliable |
| Translate at REST layer (one-shot per request) | Repeats work, no audit history; canonical store stays R5 per ADR-013 |
| Use base R4 extension namespace `http://hl7.org/fhir/4.0/StructureDefinition/extension-{path}` | HL7 has no official R4↔R5 extension registry; using our own namespace avoids implying false endorsement |
| Allow `unimplemented!()` placeholders past Sprint 2 | Macro guard forbids it; every field must have a category + rule from day one |

## Consequences

**Positive:**

- Compile-time exhaustiveness guarantee against FHIR field drift
- Every lossy event is auditable, regulator-traceable, customer-visible
- Symmetric R4↔R5 from Sprint 2 — Sprint 9 Smart-on-FHIR has no asymmetric design debt
- Open-source-friendly: the extension namespace registry is publishable as a Thai R5 community contribution
- Reverse audit usefulness: customers learn about their EHR data quality from `fhir.translation.warning` aggregation

**Negative:**

- 50 golden cases × 2 resources = 100 cases to author in Sprint 2 (synthetic generator amortizes this)
- Macro adds compile-time cost; mitigated by feature-gating in test/dev builds
- Tyr event volume grows ~ R4 ingest volume; ensure Wazuh retention sizing accounts for it
- Extension namespace registry documentation becomes a maintenance commitment

**Neutral / TBD:**

- Whether the `fhir-r4r5-extensions.md` registry is published as a separate doc or absorbed into the conformance suite — defer to Sprint 2 Day 8
- Whether to publish the macro and types as an open-source crate (`asgard-fhir-translate`) — defer until Sprint 5 (post-20-resource scope completion)

## Sprint 2 deliverables

| Day | Task |
|---|---|
| 1 | This ADR accepted; `translate/mod.rs` trait + `LossyRule` + `TranslationResult` + macro skeleton |
| 2-3 | `translate/patient.rs` + 50 golden cases (Patient is mostly identical — proves framework) |
| 4-6 | `translate/encounter.rs` + 50 golden cases (Encounter is the hard case — proves framework under stress) |
| 7 | Tyr audit hook + `fhir.translation.warning` event emitter |
| 8 | `docs/architecture/fhir-r4r5-extensions.md` namespace registry document |
| 9-10 | E2E roundtrip benchmark (target ≥1000 resources/sec, Mac mini M2 baseline) + Mimir PR ready |

## Validation criteria

This ADR is validated when:

- [ ] `translate/mod.rs` defines 8 categories + 4 severity levels as Rust enums
- [ ] `translation_map!` macro compile-fails on missing or unknown fields
- [ ] Patient translator achieves Tier 1 + Tier 2 roundtrip on 50 cases
- [ ] Encounter translator achieves Tier 1 + Tier 2 + Tier 3 on 50 cases
- [ ] At least one `LossyDrop` is documented in this ADR or a sub-ADR with reason string visible in code
- [ ] Tyr receives `fhir.translation.warning` events from at least one E2E translation run
- [ ] `fhir-r4r5-extensions.md` registry lists every `LossyWithExtension` URL used in Sprint 2

## References

- [ADR-006](ADR-006-fhir-canonical-design.md) — FHIR canonical design (R5 per ADR-013 amendment)
- [ADR-013](ADR-013-fhir-r5-canonical-version.md) — R5 canonical version lock
- [ADR-014](ADR-014-fhir-data-plane-ownership.md) — FHIR data plane ownership (Mimir family)
- [ADR-016](ADR-016-asgard-fhir-profile-family.md) — Asgard FHIR profile family (TH Core + MoPH-PC binding)
- HL7 FHIR R4→R5 diff — http://hl7.org/fhir/R5/diff.html
- MOPH-PC1 mapping — `docs/architecture/moph_pc1_fhir_mapping.md`
- Translation framework code — `crates/mimir-fhir/src/translate/` (Sprint 2)
- Golden corpus — `crates/mimir-fhir/tests/golden/` (Sprint 2)
- Extension namespace registry — `docs/architecture/fhir-r4r5-extensions.md` (Sprint 2 Day 8)