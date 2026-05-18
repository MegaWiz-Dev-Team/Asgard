# ADR-003: Trait-based Extraction & Shared `asgard-doc-pipeline` Crate

**Status:** Accepted
**Date:** 2026-05-17
**Deciders:** paripol@megawiz.co
**Context for:** Asgard-Underwriter v3 Phase B + Medical Chart OCR (Syn extension) + future Mega Care portal bridge
**Related:** [ADR-001](ADR-001-database-choice.md), [ADR-002](ADR-002-audit-sink-architecture.md), [feedback_consolidate_overlap_early memory](memory)

## Context

Asgard has at least three workstreams that need essentially the same document pipeline:

1. **Asgard-Underwriter** — claim/policy/medical-record document ingestion for insurance underwriting
2. **Medical Chart OCR (Syn extension)** — handwritten doctor chart OCR for medical platform deployments
3. **Mega Care portal bridge (future)** — patient document flow from sleep clinic portal into Asgard medical workflow

Audit of Asgard-Underwriter v2.2.1 found `iris/src/extraction.rs` is **~60% generic, ~40% tangled with underwriting workflow** (ICD-10 mapping, risk scoring, insurance scoring assumptions baked in alongside generic Syn/Mimir orchestration).

User has decided ([feedback_consolidate_overlap_early memory](memory)) that overlapping pipelines should be consolidated **upfront** rather than allowed to fork-then-converge. The principle is recorded; this ADR specifies how.

## Decision

Refactor `iris/src/extraction.rs` to trait-based design, then **extract a shared workspace crate `asgard-doc-pipeline` and publish to crates.io as AGPL-3.0 + Commercial dual** (per [feedback_asgard_license memory](memory)).

### Crate workspace structure

```
asgard-doc-pipeline/                       (workspace root)
├── Cargo.toml                             (workspace manifest)
├── README.md
├── LICENSE-AGPL.md
├── LICENSE-COMMERCIAL.md
└── crates/
    ├── core/                              # asgard-doc-pipeline-core
    │   ├── traits.rs                      # DocumentSource, OcrBackend, PiiGate, ...
    │   ├── types/
    │   │   ├── fhir/                      # FHIR R4 resources (~15 selected)
    │   │   ├── thai/                      # Thai profile (citizen_id, address)
    │   │   └── ocr.rs                     # OcrOutput, Confidence, Bbox
    │   └── audit.rs                       # AuditEvent shape (consumer of ADR-002 sink)
    │
    ├── ocr-syn/                           # asgard-doc-pipeline-ocr-syn
    │   └── ...                            # Syn HTTP client impl of OcrBackend
    │
    ├── pii-skuggi/                        # asgard-doc-pipeline-pii-skuggi
    │   └── ...                            # Skuggi adapter impl of PiiGate
    │
    ├── audit-tyr/                         # asgard-doc-pipeline-audit-tyr
    │   └── ...                            # AuditSink impls (LocalDb, Wazuh stub, Fanout) — moved from Underwriter once stable
    │
    ├── storage/                           # asgard-doc-pipeline-storage
    │   └── ...                            # DB abstraction (MariaDB-first, Postgres-ready) — sqlx traits
    │
    ├── lexicon-primekg/                   # asgard-doc-pipeline-lexicon-primekg
    │   └── ...                            # PrimeKG-backed LexiconValidator
    │
    └── pipeline/                          # asgard-doc-pipeline (composed default)
        ├── default.rs                     # Wires core + Syn + Skuggi + Tyr + storage
        └── examples/
            └── minimal-pipeline.rs        # Smoke test: file → extracted FHIR Bundle
```

### Core traits

```rust
// crates/core/src/traits.rs

#[async_trait]
pub trait DocumentSource: Send + Sync {
    fn file_type(&self) -> FileType;
    fn bytes(&self) -> &[u8];
    fn hash(&self) -> &str;            // SHA-256 hex of bytes
    fn metadata(&self) -> &DocumentMetadata;
}

#[async_trait]
pub trait OcrBackend: Send + Sync {
    async fn extract(&self, src: &dyn DocumentSource) -> Result<OcrOutput>;
    fn name(&self) -> &str;            // "syn-typhoon", "tesseract", ...
    fn confidence_threshold(&self) -> f32;
}

#[async_trait]
pub trait PiiGate: Send + Sync {
    async fn check_text(&self, text: &str) -> PiiResult;
    async fn check_image(&self, src: &dyn DocumentSource) -> PiiResult;
    /// Pixel-blackout regions in image; returns redacted bytes.
    async fn redact_pixels(&self, src: &dyn DocumentSource, regions: &[Bbox]) -> Result<Vec<u8>>;
}

#[async_trait]
pub trait LexiconValidator: Send + Sync {
    /// Re-rank OCR candidates against a domain lexicon (e.g., PrimeKG, insurance terms).
    /// Returns same candidates with adjusted confidence scores.
    async fn validate(&self, candidates: Vec<Candidate>) -> Result<Vec<Candidate>>;
}

#[async_trait]
pub trait DisambiguationAgent: Send + Sync {
    /// For low-confidence tokens, use surrounding context to propose better candidates.
    async fn disambiguate(&self, ctx: &DocumentContext, token: &UncertainToken)
        -> Result<DisambiguationResult>;
}

#[async_trait]
pub trait StructuredExtractor<T>: Send + Sync {
    /// Convert raw OCR output + validated lexicon hits into domain-specific structured data.
    async fn extract_structured(&self, ocr: &OcrOutput) -> Result<T>;
}
```

### What stays Underwriter-specific (does NOT move to shared crate)

```rust
// iris/src/extraction.rs (after refactor)

pub struct InsuranceClaimData {
    pub diagnoses: Vec<Diagnosis>,           // ICD-10-TM coded
    pub medications: Vec<Medication>,        // TMT coded
    pub labs: Vec<Lab>,                      // LOINC coded
    pub procedures: Vec<Procedure>,          // TPC coded
    pub provider: Provider,
    pub coverage: Option<Coverage>,
    pub risk_factors: Vec<RiskFactor>,       // Underwriting-specific
}

pub struct UnderwriterExtractor { /* deps */ }

#[async_trait]
impl StructuredExtractor<InsuranceClaimData> for UnderwriterExtractor {
    async fn extract_structured(&self, ocr: &OcrOutput) -> Result<InsuranceClaimData> {
        // Underwriting-specific orchestration: ICD-10 lookup, drug normalization,
        // risk scoring inputs, FHIR Claim resource shaping
        ...
    }
}
```

Medical chart OCR will define its own `ClinicalChartData` extractor that ALSO uses the shared crate. Mega Care portal bridge will use `StructuredExtractor<SleepStudyData>` later.

### Publishing strategy

**crates.io public from v0.1.0**, AGPL-3.0 + Commercial dual license (per [feedback_asgard_license memory](memory)).

- `v0.1.x` — experimental API, breaking changes allowed (semver allows this pre-1.0)
- `v1.0.0` — locked after Underwriter v3 ships AND medical chart OCR ships AND used in anger for at least 2 sprints
- License headers on every file; LICENSE-AGPL.md + LICENSE-COMMERCIAL.md at workspace root

## Alternatives Considered

### 1. Fork from Underwriter, consolidate later (rejected — earlier decision)

User explicitly rejected this 2026-05-17 in conversation, leading to memory `feedback_consolidate_overlap_early`. ADR-003 codifies that decision.

### 2. Keep monorepo, no separate crate (rejected)

- Put traits in Underwriter, have medical chart OCR depend on Underwriter

**Why rejected:**
- Forces medical chart OCR to pull insurance dependencies it doesn't need
- Underwriter becomes a load-bearing public dependency for medical chart pipelines
- Discourages clean separation (slippery slope back to tangle)

### 3. Single mega-crate instead of workspace (rejected)

- All traits + Syn adapter + Skuggi adapter + storage in one crate

**Why rejected:**
- Consumers (medical chart OCR, Mega Care bridge) drag in all adapters even if they only use one
- Compile time explodes
- Update churn: bumping the Syn adapter forces all consumers to recompile
- Workspace with feature-flagged sub-crates is the Rust idiom for this

### 4. Internal git dependency (no crates.io) (rejected)

- Workspace, but don't publish

**Why rejected:**
- Friction for any external collaborator
- crates.io is the discovery surface; user wants Asgard visible per AGPL+Commercial moat (memory `feedback_asgard_license`)
- Versioning discipline weaker on git deps
- Lock-step updates harder

### 5. Wait until Underwriter v3 ships, then extract (rejected)

- Refactor + extract is risky; do it after stabilizing v3

**Why rejected:**
- Refactor cost grows with code drift
- Medical chart OCR (W3) is gated on the shared crate; deferring extraction delays W3 by weeks
- Underwriter v3 Phase B is the right slot — it includes the trait refactor anyway

## Consequences

### Positive

- **DRY across workstreams** — Underwriter, medical chart OCR, Mega Care bridge consume one library
- **License + moat** — public AGPL crate is the open-core surface; commercial license is the revenue surface
- **Forced abstraction discipline** — extracting to a separate crate stops you from sneaking in domain-specific types
- **External adoption surface** — third parties (other Thai medical AI startups, hospital integrators) can build on the same pipeline
- **Test isolation** — shared crate has its own mocks + integration tests; consumers can mock the trait surface
- **FHIR canonical model** — single place where FHIR R4 + Thai profile types live; consumers all see the same shapes (per [ADR-006 planned](ADR-006-fhir-r4-canonical.md))

### Negative

- **Workspace complexity** — 7 crates is more ceremony than 1; needs Cargo.toml hygiene + versioning discipline
- **Cross-crate breaking changes** — bumping core requires bumping all consumers; semver tooling helps but discipline needed
- **Initial extraction cost** — refactor `extraction.rs` to traits + move to workspace + republish is ~3-5 days (per [underwriter_v3_plan_decisions memory](memory))
- **Public API responsibility** — once on crates.io, breaking changes require version bump + migration notes; cannot silently refactor

### Risks

- **API design lock-in** — early traits may be wrong; v0.1.x lets us iterate, but a bad v1.0 lockout is painful. Mitigation: don't tag v1.0 until proven across ≥2 consumers (Underwriter + medical chart OCR)
- **License complexity** — AGPL+Commercial dual licensing for a public crate has nuances around redistribution. Mitigation: clear LICENSE files + FAQ + legal review before v1.0
- **Performance overhead from trait dispatch** — async trait objects have allocation cost. Mitigation: hot-path benchmarks before lock; consider monomorphization for known-static cases

## Migration Plan

(Maps to Underwriter v3 Phase B per [sprint_tracker_2026_05_17.md](../sprint_tracker_2026_05_17.md))

### B.1 — Refactor in-place (3-4 days, no crate extraction yet)

1. Define traits inside `iris/src/pipeline/` as a new module
2. Refactor `extraction.rs` to implement traits + remove direct Syn/Mimir/Skuggi calls
3. Mock implementations for tests
4. **Regression gate:** all 159 backend tests + 10 E2E pass

### B.2 — Extract to workspace + publish (3-5 days)

1. Create `asgard-doc-pipeline/` workspace at `/Users/mimir/Developer/asgard-doc-pipeline/` (or under Asgard org repo)
2. Move generic traits + types + adapters from Underwriter into respective crates
3. Underwriter's `Cargo.toml` adds path dependency on the workspace
4. **Regression gate:** Underwriter regression suite passes
5. Build `cargo doc --no-deps` — public API renders cleanly
6. Add `examples/minimal-pipeline.rs` — must compile and run
7. Publish v0.1.0 to crates.io

### B.3 — FHIR R4 types (3-5 days, can overlap with B.1/B.2)

Selection list locked in W2.4 task (per sprint tracker). 15 resources:

- Foundation: `Resource`, `DomainResource`, `CodeableConcept`, `Coding`, `Identifier`, `Reference`, `Period`
- Clinical: `Patient`, `Encounter`, `Observation`, `Condition`, `MedicationRequest`, `MedicationStatement`, `DiagnosticReport`, `DocumentReference`, `Procedure`, `Practitioner`, `Organization`
- Financial: `Coverage`, `Claim`, `ClaimResponse`, `ExplanationOfBenefit`, `Contract`
- Workflow: `Appointment`, `Task`

Thai profile: ThaiPatient (citizen_id format, Thai address structure, Thai name parts), ThaiCondition (ICD-10-TM bound), ThaiMedicationRequest (TMT bound).

## Validation

This decision is validated when:

- [ ] `cargo workspace` builds clean
- [ ] Underwriter 159 backend + 10 E2E tests pass with refactored code
- [ ] `cargo doc --no-deps` renders core API readably
- [ ] `examples/minimal-pipeline.rs` runs end-to-end on synthetic input
- [ ] v0.1.0 published to crates.io with both LICENSE files
- [ ] Medical chart OCR (W3) can consume the crate without touching Underwriter
- [ ] No insurance/underwriting types leak into `core` crate (grep audit)

## References

- [feedback_consolidate_overlap_early memory](memory) — origin decision
- [feedback_asgard_license memory](memory) — AGPL + Commercial dual
- [underwriter_v3_plan_decisions memory](memory) — Phase B scope
- [ADR-001](ADR-001-database-choice.md) — DB layer the storage crate adapts
- [ADR-002](ADR-002-audit-sink-architecture.md) — AuditSink trait the audit-tyr crate hosts
- [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md) — per-deployment crate, no multi-tenant magic
