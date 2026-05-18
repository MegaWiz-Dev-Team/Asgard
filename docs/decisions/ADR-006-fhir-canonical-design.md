# ADR-006: FHIR R4 Canonical Design — Locked Decisions

**Status:** Accepted
**Date:** 2026-05-18
**Deciders:** paripol@megawiz.co
**Scope:** `asgard-doc-pipeline-core` FHIR types implementation
**Sprint:** 2 W2.6
**Related:** [ADR-003 Shared crate boundary](ADR-003-shared-doc-pipeline-crate.md), [FHIR R4 resource selection](../architecture/fhir_r4_resource_selection.md), [ADR-002 Audit sink](ADR-002-audit-sink-architecture.md)

## Context

[W2.4 FHIR R4 resource selection](../architecture/fhir_r4_resource_selection.md) locked the 15-resource set + Thai profile bindings but parked 5 design questions:

1. **Bundle.entry typing** — closed enum vs `Box<dyn Resource>`?
2. **Resource versioning** — track `meta.versionId` in-resource vs audit-via-Tyr?
3. **JSON Schema generation** — auto-derive via `schemars` or skip?
4. **Parsing strictness** — deny-unknown-fields vs allow-and-ignore?
5. **i18n / locale** — plain `String` + FHIR `_language` vs typed `Locale` enum?

This ADR locks all 5. Implementation in Phase B.3 follows these decisions verbatim.

## Decision summary

| # | Question | Decision |
|---|---|---|
| 1 | Bundle.entry typing | **Closed enum** with `#[serde(tag = "resourceType")]` |
| 2 | Resource versioning | **Audit-via-Tyr** (per ADR-002 hash chain); `meta` fields generated on-demand |
| 3 | JSON Schema | **`schemars` derive** on every Rust type + manual annotation overrides for FHIR cardinality semantics |
| 4 | Parsing strictness | **Hybrid** — strict outbound (`deny_unknown_fields`), lenient inbound (separate `External*` newtype) |
| 5 | i18n / locale | **Plain `String` + FHIR `_language` extension** for fields that need locale; multi-locale HumanName uses repeated entries |

## Decision 1 — Bundle.entry typing

### Chosen: Closed enum

```rust
#[derive(Debug, Clone, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "resourceType")]
pub enum BundleEntry {
    Patient(Patient),
    Encounter(Encounter),
    Observation(Observation),
    Condition(Condition),
    MedicationRequest(MedicationRequest),
    MedicationStatement(MedicationStatement),
    Procedure(Procedure),
    DiagnosticReport(DiagnosticReport),
    AllergyIntolerance(AllergyIntolerance),
    DocumentReference(DocumentReference),
    Coverage(Coverage),
    Claim(Claim),
    ClaimResponse(ClaimResponse),
    Practitioner(Practitioner),
    Organization(Organization),
}
```

### Why

- **Exhaustive match safety** — compiler refuses to ignore new variants when we add one. Critical for safety-sensitive code paths (pharmacy DDI, claim adjudication).
- **No virtual dispatch** — match is a jump table; no vtable indirection.
- **Serde-friendly** — `#[serde(tag = "resourceType")]` is the FHIR convention. Deserialization picks the right variant from the JSON `resourceType` discriminator. One annotation, fully automatic.
- **Size cost negligible** — 15 variants × largest-resource (~Claim, ~2KB) = ~2KB enum size. Heap-allocate if needed, but stack is fine for ingest pipeline.
- **Refactoring discipline matches our scope** — 15 resources is small enough that "touch every match site" is healthy friction, not a tax.

### Alternatives rejected

- **`Box<dyn Resource>`**: easier to add new resources but loses exhaustiveness; harder to serialize without external tag manually managed; runtime dispatch where compile-time would do.
- **Generic `Resource<T>`**: type-level resource kind via marker; over-engineered for a 15-resource scope.
- **`enum_dispatch` macro**: gets us trait-method dispatch on the enum but unnecessary when the enum is the canonical representation.

### Consequences

- Adding a new resource = touching `BundleEntry` enum + all match sites in `validate_bundle`, `to_json`, `from_json`. Acceptable.
- External code that wants to receive arbitrary `BundleEntry` cannot ignore unknown variants — the enum is closed. This is the safety property we want.

## Decision 2 — Resource versioning

### Chosen: Audit-via-Tyr (no in-resource version tracking)

Asgard does NOT track `meta.versionId` or `meta.lastUpdated` as authoritative state on the resource itself. The resource row in the database is always the **current** state. Historical state is reconstructible from the [Tyr audit hash chain](ADR-002-audit-sink-architecture.md).

```rust
pub struct Meta {
    // FHIR R4 fields, all serialized when emitting FHIR JSON:
    pub version_id: Option<String>,        // derived on-demand from audit, NOT stored
    pub last_updated: Option<DateTime<Utc>>, // ditto
    pub source: Option<String>,
    pub profile: Vec<String>,              // canonical URLs of conformed profiles
    pub security: Vec<Coding>,
    pub tag: Vec<Coding>,
}
```

When the resource is emitted via FHIR REST endpoint (when one exists), we generate `meta.version_id` and `meta.last_updated` from the latest matching audit event:

```rust
fn fill_meta_from_audit(resource: &mut Patient, audit: &AuditService) -> Result<()> {
    let latest = audit.latest_for_resource("Patient", &resource.id).await?;
    resource.meta.last_updated = Some(latest.ts);
    resource.meta.version_id = Some(latest.event_id.to_string()); // event_id as version
    Ok(())
}
```

### Why

- **Single source of truth** — ADR-002 already requires audit logging for every PII/medical mutation. Duplicating version state in the resource creates a second source of truth that can drift.
- **Schema simplicity** — no `versions` column or history table; current-state row only.
- **Tamper evidence** — audit hash chain is the authoritative history. In-resource `versionId` is just metadata, no integrity check.
- **FHIR-compliant on read** — when we emit FHIR JSON externally, we still populate `meta.versionId` and `meta.lastUpdated`; downstream consumers don't notice.

### Alternatives rejected

- **In-resource `meta.versionId` as primary**: adds a separate version dimension to every table; doubles storage; risks audit/resource divergence.
- **Hybrid (both stored)**: requires invariant `resource.meta.lastUpdated == audit.latest.ts`; one more thing to keep in sync; easy to break under high concurrency.

### Consequences

- **Cannot answer "give me v3 of this Patient"** directly — must replay audit events to reconstruct. Acceptable for v1; if needed, add a history snapshot table later.
- Audit must be online for FHIR REST `If-Match` / ETag flows. Tyr scaled-down state (per `tyr_wazuh_scaled_down` memory) is fine because [ADR-002](ADR-002-audit-sink-architecture.md) defines a `LocalDbSink` that's always available.
- Multi-writer concurrency: optimistic concurrency control via `audit.latest.event_id` comparison (proposed update must reference the version the writer last saw). Implementation deferred to FHIR REST endpoint sprint.

## Decision 3 — JSON Schema generation

### Chosen: `schemars` derive + manual annotation overrides

```rust
use schemars::JsonSchema;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Patient {
    /// Logical ID of the patient resource. UUID or stable hash.
    pub id: Id,

    /// Business identifiers. MUST include one Thai citizen ID identifier
    /// for Thai patients.
    #[schemars(length(min = 1))]
    pub identifier: Vec<Identifier>,

    // ... rest
}
```

Schemas are generated at build time and exported to:
- `target/schemas/Patient.schema.json` (per type)
- `target/schemas/bundle.schema.json` (the closed enum)

External consumers (Hermodr MCP tool definitions, future FHIR REST clients, frontend TypeScript codegen) consume these.

### Why

- **Future-proofing** — when FHIR REST or external API surface lands, we need schemas. Hand-writing JSON Schema for 15 resources is ~1000 lines of brittle copy-paste; `schemars` derives them.
- **Cardinality annotations** — FHIR has `0..1`, `1..1`, `0..*`, `1..*`; Rust's `Option<T>` and `Vec<T>` map to 0..1 and 0..*. The remaining 1..1 / 1..* cases need `#[schemars(length(min = N))]` or `#[schemars(skip_serializing_if = ...)]`. Manageable manually for 15 resources.
- **MCP tool schemas** — Hermodr W2.5 manually wrote 6 PrimeKG tool schemas as inline `serde_json::json!`. Phase B.3 can switch to `schemars`-generated schemas for FHIR-shaped tool I/O.
- **TypeScript codegen** — JSON Schema → `quicktype` or `json-schema-to-typescript` for frontend types. Free.

### Alternatives rejected

- **Skip schemas (internal-only types)**: short-term-correct; future regret when first external consumer asks for them.
- **Hand-write all schemas**: ~1000 lines of repetition; drift between Rust and JSON Schema is inevitable.
- **Use `utoipa` instead of `schemars`**: OpenAPI codegen, more features, but we don't yet have a REST API to motivate it. `schemars` is the smaller dep.

### Consequences

- Compile time adds ~1-2s for `schemars` derives across all resources. Acceptable.
- Some FHIR semantics (e.g., `oneOf` for `value[x]` polymorphic fields) need manual `#[schemars(...)]` annotations. We accept ~5-10 manual annotations across the 15 resources.
- Generated JSON Schema may not match HL7's official R4 JSON Schema byte-for-byte. We document the divergence in the spec doc; consumers can choose ours or HL7's depending on use case.

## Decision 4 — Parsing strictness

### Chosen: Hybrid — strict outbound, lenient inbound via separate types

```rust
// Our own writes use strict types:
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Patient { /* ... */ }

// External FHIR ingest uses lenient parsing:
#[derive(Deserialize)]
#[serde(default)] // allow missing fields; fill with defaults
pub struct ExternalPatient {
    pub id: Option<Id>,
    pub identifier: Vec<Identifier>,
    pub name: Vec<HumanName>,
    // ... only the fields we care about; serde silently ignores extras
}

impl TryFrom<ExternalPatient> for Patient {
    type Error = ValidationError;
    fn try_from(ext: ExternalPatient) -> Result<Self, Self::Error> {
        // Validate + map to strict Patient. Logs ignored fields.
    }
}
```

### Why

- **External EHR exports include FHIR fields we don't model** (`careTeam`, `clinicalImpression`, custom extensions from a hospital's EMR profile, etc.). Refusing them = brittle integration.
- **Our own writes** going through the strict type catches typos and field drift at compile time.
- **One ingest path that handles both** would have to be lenient everywhere — losing the safety of strict types where it matters.
- **The `External*` newtype** makes the boundary explicit: in the ingest module, you parse `ExternalPatient` and convert; in the rest of the code, only `Patient` exists.

### Alternatives rejected

- **Strict everywhere with `deny_unknown_fields`**: every external integration breaks the first time the upstream adds a field. Unsustainable.
- **Lenient everywhere**: typos in our own code silently become NULLs; no compile-time safety.
- **Validation only, no separate types**: ingest gets a `Patient` with possibly-missing-required-fields; type system can't help.

### Consequences

- **Two structs per resource** (the canonical + the `External*` newtype). Some duplication. Mitigation: codegen via a macro if it gets tedious.
- Conversion logs (which external fields were ignored) help us know when to add a field to the canonical type.
- Inbound + outbound parsing paths are different code; mistakes are localized.

## Decision 5 — i18n / locale

### Chosen: Plain `String` + FHIR `_language` extension

Most fields are not localized:
- LOINC code = `8480-6` (not localized)
- ICD-10-TM code = `E11` (not localized; only the label is)
- Datetime = ISO-8601 (no locale)

For fields that ARE localized (display labels, free-text notes), we use plain `String` and rely on **separate records** for multi-language data:

```rust
// Patient with both Thai and Latin names — two HumanName entries:
patient.name = vec![
    HumanName {
        use_: NameUse::Official,
        family: "บุญส่ง".into(),
        given: vec!["กิติชัย".into()],
        language: Some("th".into()), // FHIR _language extension
        ..Default::default()
    },
    HumanName {
        use_: NameUse::Usual,
        family: "Boonsong".into(),
        given: vec!["Kittichai".into()],
        language: Some("en".into()),
        ..Default::default()
    },
];
```

For free-text notes:

```rust
condition.note = vec![
    Annotation {
        text: "ผู้ป่วยปฏิบัติตามคำแนะนำ".into(),
        language: Some("th".into()),
        author_reference: Some(Reference::practitioner(/*...*/)),
        time: Some(Utc::now()),
    },
];
```

### Why

- **FHIR R4 already defines this pattern** — the `_language` extension on primitives is canonical. Adopting it preserves interop with any external FHIR consumer.
- **Most fields aren't localized** — codes, identifiers, timestamps, numbers. Wrapping all `String`s in a `Locale`-typed newtype would be noisy.
- **Forward-compatible** — when Asgard supports Burmese, Lao, Khmer (regional expansion path), we just add new HumanName entries with `language: Some("my".into())` etc. No type changes.
- **Search semantics** — applications that need to search by language can filter on `language` field; applications that don't care just use the first entry.

### Alternatives rejected

- **`LangString { locale: Locale, text: String }` newtype**: forces every string field to think about locale even when not relevant. Noisy.
- **Enum `LangString { Thai(String), English(String), Both { th: String, en: String } }`**: closed to 2 languages; doesn't extend; mixes language-of-content with language-of-presentation.
- **Tantivy-style multi-locale indexing**: relevant for search, not for the data model. Out of scope for ADR-006.

### Consequences

- **No type-level locale safety** — a developer can put Thai in an `en`-tagged HumanName by mistake. Mitigation: validation rule at constructor `HumanName::new_thai(...)` and `HumanName::new_english(...)`; CI test verifies our test fixtures correctly tag locales.
- **Search queries need language filtering** — "find patient named Kittichai" must specify language or search across both. Acceptable for v1; index can pre-fold to lowercase Latin in a future sprint.

## Implementation order (Phase B.3)

1. **Datatypes first** (Identifier, CodeableConcept, Coding, Reference, HumanName, Address, ContactPoint, Period, Quantity, Money, Range, Annotation, Meta) — these are reused everywhere
2. **Patient + Thai profile** — gates every other clinical resource
3. **Encounter + Condition + MedicationRequest + Procedure** — clinical workflow trio
4. **Observation + DiagnosticReport + AllergyIntolerance** — investigation + safety
5. **DocumentReference + MedicationStatement** — OCR + reconciliation surface
6. **Coverage + Claim + ClaimResponse** — insurance side
7. **Practitioner + Organization** — participants
8. **Bundle enum + validation** — the unifier
9. **External\* newtypes for inbound** — once canonical types stabilize
10. **Schema export build step** — generates `target/schemas/*.json`

Per-type effort: ~0.5-1d for canonical + Thai profile + tests. Total ~10-12d for Phase B.3, matching the [Underwriter v3 plan](../../../.claude/projects/-Users-mimir-Developer/memory/underwriter_v3_plan_decisions.md) estimate of 3-5d (which was optimistic; this ADR refines).

## Validation criteria

This ADR is validated when:

- [ ] All 15 resources have both canonical and `External*` types
- [ ] `cargo build` succeeds with `schemars` derives on every resource
- [ ] Bundle round-trips: `Bundle → JSON → Bundle` is identity for the test corpus
- [ ] `ExternalPatient` parses a real EHR export (e.g., HL7 v2-translated Hosxp output) without panic
- [ ] Audit-derived `meta.versionId` matches the latest audit event hash for the resource
- [ ] Multi-locale HumanName test: one Patient with Thai + Latin names round-trips
- [ ] Generated JSON Schema validates the test corpus

## References

- [W2.4 FHIR R4 resource selection](../architecture/fhir_r4_resource_selection.md) — parked these 5 questions
- [ADR-002 Audit sink](ADR-002-audit-sink-architecture.md) — version derivation source
- [ADR-003 Shared crate boundary](ADR-003-shared-doc-pipeline-crate.md) — implementation home
- [Underwriter v3 plan memory](../../../.claude/projects/-Users-mimir-Developer/memory/underwriter_v3_plan_decisions.md) — Phase B.3 schedule
- [`schemars` crate](https://crates.io/crates/schemars) — JSON Schema derive
- FHIR R4 — http://hl7.org/fhir/R4/
