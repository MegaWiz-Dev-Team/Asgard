# ADR-019: FHIR Profile Validation — Tightest-Binding-Wins Merge Algorithm

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Defines the profile validation algorithm in `mimir-fhir` — how Base R5, TH Core (when adopted), and Asgard FHIR Profile bindings merge per field; how irreconcilable bindings are detected; the compile-time validator generation pipeline; the validator output contract; and the conformance test corpus discipline. Operationalizes [ADR-016](ADR-016-asgard-fhir-profile-family.md) D1 (Asgard Profile authoritative) and D3 (profile content scope), and unblocks Sprint 7 (profile validators).
**Related:** [ADR-006](ADR-006-fhir-canonical-design.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-016](ADR-016-asgard-fhir-profile-family.md), [ADR-017](ADR-017-fhir-r4r5-translation-framework.md)

## Context

ADR-016 established the Asgard FHIR Profile family alongside Base R5 and (optionally) TH Core. A resource validated against multiple profiles inherits constraints from each layer: cardinality, ValueSet bindings, must-support flags, slices, and fixed values. When the layers disagree, an algorithm must decide which constraint applies.

FHIR has no single normative algorithm for this. HAPI / Medplum use heuristic per-validator implementations; HL7 IG Publisher's `Snapshot` generation merges by inheritance order. Neither is well-suited to Asgard's needs:

- Asgard validates against three independent profile families (Base R5, TH Core, Asgard) without a strict inheritance chain — TH Core does not always derive from Base; Asgard does not always derive from TH Core.
- Asgard's on-prem Mac mini constraint demands compile-time generation, not runtime profile interpretation.
- Asgard's audit posture ([ADR-014](ADR-014-fhir-data-plane-ownership.md)) requires every issue to be traceable to a specific profile + constraint, not aggregated.

Without an algorithm lock, Sprint 7 implementation would diverge per resource; profile drift between Asgard and MOPH (when TH Core publishes) would cause silent validation gaps at hospital sites.

## Decision

Profile validation uses a **tightest-binding-wins merge algorithm** applied uniformly across all profile layers and all binding dimensions. Irreconcilable bindings fail at compile time. Validators are generated as Rust code from JSON profile artifacts via `build.rs`.

### D1. Profile cascade — symmetric, no authoritative override

Three profile layers participate in validation:

| Layer | Source | Always present? |
|---|---|---|
| A | Base R5 (HL7 FHIR core) | Yes |
| B | TH Core (MOPH-published) | Only for fields TH Core profiles |
| C | Asgard FHIR Profile | Yes |

Layers are **symmetric** — Layer C does not override Layer B or A by virtue of being Asgard's. The tightest-binding-wins rule applies uniformly. If TH Core publishes a stricter ValueSet on `Patient.identifier` than Asgard's, TH Core wins on that field even though Asgard is "our" profile.

This preserves the property that adding TH Core profiles to a deployment never weakens validation. Asgard cannot accidentally relax a MOPH-imposed constraint by editing its own profile.

ADR-016 D1 ("Asgard FHIR Profile = authoritative") is reinterpreted: Asgard owns the profile family identity, naming, publishing schedule, and version cadence — but not constraint override authority over MOPH-published binding-tighter constraints. Authority over governance, not over individual binding values.

MoPH-PC1 mapping is informative-only per [ADR-016](ADR-016-asgard-fhir-profile-family.md) D2 and does NOT participate in the validation cascade.

### D2. Six-dimension binding merge

Every field constraint is decomposed into six dimensions. The merge algorithm is applied per dimension:

| Dimension | Merge rule | Result type |
|---|---|---|
| Strength | `max()` over `{required > extensible > preferred > example}` | binding-strength enum |
| ValueSet | depends on merged strength (see [D3](#d3-valueset-merge-by-strength)) | URI + expansion or `null` |
| Cardinality.min | `max()` of all layers' min | non-negative int |
| Cardinality.max | `min()` of all layers' max (`*` treated as ∞) | int or `*` |
| Must-support | logical OR | bool |
| Fixed value | all-layers-must-agree, else BUILD ERROR | concrete value |

Slices use this same algorithm applied recursively to the slice's own field constraints. Discriminator types must agree across layers or BUILD ERROR.

### D3. ValueSet merge by strength

After strength is merged via `max()`, the ValueSet merge follows this matrix:

| Effective strength | All layers agree on ValueSet | Layers have different ValueSets |
|---|---|---|
| `required` | use that ValueSet | **intersect** all required-strength ValueSets. Empty intersection = BUILD ERROR. |
| `extensible` | use that ValueSet | **union** all extensible-strength ValueSets (lenient — fallback allowed beyond union) |
| `preferred` | use that ValueSet | use the ValueSet from the highest-priority layer with `preferred` (Asgard > TH Core > Base) — soft hint only |
| `example` | use that ValueSet | discard ValueSet; binding becomes informative only |

When a layer's effective strength is below the merged strength, that layer's ValueSet is discarded (e.g., if Base = `extensible` and Asgard = `required`, Asgard's ValueSet wins, Base's is dropped).

The build pipeline materialises each `required` ValueSet expansion at compile time. Disjoint required ValueSets are detected during this materialisation pass.

### D4. Cardinality conflict

If `merged.min > merged.max`, the profile combination is irreconcilable — BUILD ERROR. Example:

```
Asgard:   Encounter.identifier  2..*
TH Core:  Encounter.identifier  0..1
          ──────────────────────────
          merged.min = max(2, 0) = 2
          merged.max = min(*, 1) = 1
          2 > 1  ──→  BUILD ERROR
```

This is a profile-author bug. The fix is to relax one profile or document the divergence, not to silently pick one side.

### D5. Build-time, not runtime

Validators are generated by `mimir-fhir/build.rs` (or equivalent proc-macro) at `cargo build` time:

```
profiles/asgard/v0.1.0/{Resource}.profile.json
profiles/th-core/v{adopted}/{Resource}.profile.json   (optional)
hl7/r5/spec/{Resource}.profile.json                    (vendored)
                    ↓
            build.rs profile merger
                    ↓
        src/validators/_generated/{resource}.rs
                    ↓
            fn validate_{resource}(r: &R) -> ValidationReport
```

Compile-time generation is mandatory. Runtime profile loading is rejected because:

- A profile load failure at hospital startup is a deployment incident, not a build failure
- Validator performance must be predictable (no runtime profile-tree walks)
- Profile version is statically known and pinned in the binary's audit metadata

Profile update flow: bump profile JSON → rebuild `mimir-fhir` → push new container/binary. No hot-reload.

### D6. Validation result contract

Validators return a typed report. No bare booleans, no string error lists.

```rust
pub struct ValidationReport {
    pub issues: Vec<ValidationIssue>,
    pub profile_versions: Vec<ProfileVersion>,
    pub validated_at: DateTime<Utc>,
}

pub struct ValidationIssue {
    pub severity: Severity,             // Fatal | Error | Warning | Information
    pub code: IssueCode,                // FHIR OperationOutcome.issue.code
    pub field_path: FhirPath,           // typed FHIRPath, not string
    pub message: String,
    pub source_profile: ProfileId,      // which profile raised it
    pub source_constraint: ConstraintId, // which constraint within that profile
    pub effective_binding: EffectiveBinding, // the merge result that the value violated
}

pub struct ProfileVersion {
    pub layer: ProfileLayer,            // A | B | C
    pub profile_id: ProfileId,
    pub version: String,                // semver string
    pub hash: [u8; 32],                  // SHA-256 of profile JSON
}
```

Conversion to FHIR `OperationOutcome` is provided as a `From` impl so external clients see standard FHIR output when `$validate` is exposed (see [D8](#d8-validate-rest-endpoint-deferred-to-sprint-9)).

### D7. Build-error policy

Irreconcilable profile bindings fail the build. No runtime fallback, no warning escalation. The categories that produce BUILD ERROR:

| Category | Example |
|---|---|
| Disjoint required ValueSets | Layer A = required(LOINC vital-signs); Layer C = required(SNOMED procedures) |
| Cardinality min > max after merge | Asgard min=2, TH Core max=1 |
| Fixed value mismatch | Layer A fixes status='active'; Layer C fixes status='entered-in-error' |
| Slice discriminator type mismatch | Layer A uses `value`; Layer C uses `pattern` |
| Slice with same name, irreconcilable nested constraints | per-slice merge fails |

Build errors include the conflicting layers and constraints in the error message. Asgard's CI runs the build on every PR — any profile change that introduces irreconcilability fails CI before merge.

This policy is symmetric across layers. A MOPH TH Core update can fail Asgard's build if it conflicts with Asgard's profile. That is the intended signal — Asgard must reconcile, not paper over.

### D8. `$validate` REST endpoint — deferred to Sprint 9

The FHIR `$validate` operation exposes the validator at `/fhir/R5/{Resource}/$validate`. Sprint 7 ships the validator as internal Rust API only. `$validate` REST exposure is deferred to Sprint 9 (Smart-on-FHIR integration) — at that point external EHR clients have a use case for it.

The internal API is stable; Sprint 9's work is REST routing + OperationOutcome serialisation, not algorithm changes.

### D9. Performance target

Validators must achieve **≥1,000 resources/sec** on the Mac mini M2 baseline for the 21-resource scope. Measured via `criterion` benchmark on synthetic corpus. This target supports CDS real-time (single-resource per call) plus moderate batch workloads.

Higher throughput (≥10,000/sec for bulk ingest) is a Sprint 8 (43Files adapter) optimisation candidate, not a Sprint 7 commitment. Compile-time generation gives us headroom — runtime cost is dominated by serde JSON parsing, not validator logic.

### D10. Audit emission via Tyr

Every `ValidationIssue` with `severity ≥ Warning` becomes a Tyr event:

```
event_type:   fhir.validation.issue
fields:
  severity:        "Warning" | "Error" | "Fatal"
  code:            issue code
  resource_type:   "Patient" | ...
  field_path:      "Patient.identifier[0].system"
  source_profile:  "asgard/v0.1.0" | "th-core/v0.x" | "base-r5"
  source_constraint: constraint id
  patient_hash:    sha256(citizen_id) when applicable (via Skuggi)
  request_trace_id: from heimdall-trace
```

Tyr aggregates these into a data-quality dashboard. Customers see "12% of Patients arriving from EHR X lack TH Core required citizen ID slice" without exposing PHI.

`Information`-severity issues are not audited (volume noise).

## Why this algorithm over alternatives

| Alternative | Reason rejected |
|---|---|
| Asgard authoritative override (Layer C always wins) | Allows Asgard to accidentally relax MOPH-imposed constraints; breaks the "TH Core update never weakens validation" property |
| Inheritance chain (Base ← TH Core ← Asgard) | Implies Asgard derives from TH Core, which is false in ADR-016 — Asgard is informed by, not derived from |
| Runtime profile interpretation | Performance unpredictable; profile load failure becomes deployment risk; not testable at build |
| HAPI / Medplum-style per-resource heuristics | Inconsistent — different resources would resolve conflicts differently; impossible to audit policy |
| Runtime warning instead of build error | Hospital site sees silent validation drift on profile update; build error forces reconciliation at PR time |
| Aggregate validation result (bool + error string) | Loses traceability — cannot tell which profile flagged a field; defeats audit story |

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Allow runtime profile selection (`?_profile=...`) | Profile is part of the deployment, not the request. Per-request profile = configuration complexity |
| Validate MoPH-PC1 as a profile layer | MoPH-PC1 is informative-only per ADR-016 D2; would conflict with Asgard / TH Core and produce false positives |
| Cache validator results across requests | Validator is fast; cache invalidation on resource update is more complex than re-validating |
| Skip validation for write-then-read internal traffic | All resources entering the canonical store validate, no exceptions. Internal-bypass is how silent data drift happens |
| Use FHIR IG Publisher's snapshot generation | Snapshot generation is for human-readable IG output, not for runtime validation; algorithm semantics don't match our needs |

## Consequences

**Positive:**

- Symmetric algorithm — predictable behaviour, no special cases to memorise
- Build-time conflict detection — every profile change is exercised at PR CI; no silent drift
- Per-issue audit traceability — Tyr dashboard shows exactly which profile caught what
- Compile-time generation — no runtime parsing overhead; binary carries pinned profile versions
- TH Core adoption is additive — adding TH Core to a deployment can only strengthen validation, never weaken it
- Profile updates are an explicit release step (rebuild binary), aligning with the Asgard SemVer release process

**Negative:**

- Profile updates require recompilation + redeploy — no hot-reload
- A MOPH TH Core update that conflicts with Asgard breaks the build — requires reconciliation by Asgard team
- Build-error message quality matters — profile authors need clear feedback (CI test that intentional-conflict cases produce expected error)
- 21 resources × at least 3 profile JSONs = 63 JSON artifacts to maintain (mitigated by JSON generation from TypeScript/CLI templates in later sprints)

**Neutral / TBD:**

- Whether validators emit `Warning`-severity issues for "lenient" violations (e.g., `extensible` ValueSet miss) — defer to Sprint 7 detail design
- Whether to publish StructureDefinition resources (ADR-016 D5 Option A vs B) — independent of this ADR
- Whether per-customer profile override (e.g., a hospital wanting laxer constraints) is supported — defer to Phase 2 (no current customer ask)

## Sprint 7 deliverables

| Day | Task |
|---|---|
| 1 | This ADR accepted; `build.rs` skeleton + `ValidationReport` types defined |
| 2-3 | Profile merger implementation: 6-dimension merge + ValueSet intersection + cardinality conflict detection |
| 4-5 | Validator code generator: emit `_generated/{resource}.rs` for the 21 resources |
| 6 | OperationOutcome `From` impl (internal use; REST endpoint deferred to S9) |
| 7 | Conformance corpus authoring: ≥5 positive + ≥5 negative + ≥3 conflict per resource |
| 8 | `criterion` benchmark hitting ≥1,000 resources/sec on Mac mini M2 baseline |
| 9 | Tyr `fhir.validation.issue` event emitter |
| 10 | PR ready; profile version hash pinned in binary; CI builds catch intentional-conflict regression |

## Validation criteria

This ADR is validated when:

- [ ] `build.rs` profile merger compiles and runs on every `cargo build`
- [ ] At least one intentional disjoint-required-ValueSet test profile produces BUILD ERROR with conflicting layer information
- [ ] At least one intentional cardinality min > max test profile produces BUILD ERROR
- [ ] 21 resource validators generated; each compiles to a function with statically typed `ValidationReport` return
- [ ] Conformance corpus: positive cases produce zero `Error`/`Fatal` issues; negative cases produce exactly the expected issue list
- [ ] Benchmark: ≥1,000 resources/sec on Mac mini M2 for Patient, Encounter, Observation, Condition, MedicationStatement
- [ ] Tyr receives at least one `fhir.validation.issue` event during E2E run
- [ ] Profile version registry shows pinned versions for layers A, B (when adopted), C
- [ ] CI fails when a PR introduces an irreconcilable profile change

## References

- [ADR-006](ADR-006-fhir-canonical-design.md) — FHIR canonical design
- [ADR-013](ADR-013-fhir-r5-canonical-version.md) — R5 canonical version
- [ADR-014](ADR-014-fhir-data-plane-ownership.md) — Data plane ownership
- [ADR-016](ADR-016-asgard-fhir-profile-family.md) — Asgard FHIR Profile family + cascade scope
- [ADR-017](ADR-017-fhir-r4r5-translation-framework.md) — R4↔R5 translation framework (parallel discipline)
- FHIR R5 binding strength — http://hl7.org/fhir/R5/codesystem-binding-strength.html
- FHIR R5 ElementDefinition — http://hl7.org/fhir/R5/elementdefinition.html
- FHIR R5 `$validate` operation — http://hl7.org/fhir/R5/resource-operation-validate.html
- HL7 IG Publisher snapshot generation (reference, not adopted) — https://github.com/HL7/fhir-ig-publisher
- Asgard FHIR Profile artifacts — `crates/mimir-fhir/profiles/asgard/` (Sprint 7)
- Generated validators — `crates/mimir-fhir/src/validators/_generated/` (Sprint 7)
- Conformance corpus — `crates/mimir-fhir/tests/conformance/` (Sprint 7)
