# Mimir-FHIR Phase 1 — Implementation Plan

**Status:** Draft v1
**Date:** 2026-05-24
**Owner:** paripol@megawiz.co
**Scope:** Sprint-by-sprint implementation plan for Phase 1 of [ADR-012](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md). Delivers the `mimir-fhir` v0 foundation (Rust submodule of Mimir) — FHIR R5 type system for 20 resources, R4↔R5 translator, REST endpoint, 43Files-to-FHIR adapter, MOPH-PC1 conformance suite, Smart-on-FHIR launch from OpenEMR.
**Gating:** Cannot start until **all three** are green:
1. S1 Go/No-Go (2026-06-12) — medical retrieval Hit Rate@3 ≥ 75% baseline
2. Insurance Launch S52-54 stable in production
3. Living Evidence S55-58 wrap (Mimir Guideline Lineage + mimir-well + mimir-curator shipped)
**Estimated start:** Q3-Q4 2026
**Estimated duration:** 10 sprints × 2 weeks = ~20 weeks calendar (solo dev, account for context switches and Megawiz other commitments). Pure engineering effort ~14 weeks if 100% focused.
**Related:** [ADR-006](../decisions/ADR-006-fhir-canonical-design.md), [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md), [MOPH-PC1 mapping](../architecture/moph_pc1_fhir_mapping.md), [as-is-problem-analysis](../use-cases/as-is-problem-analysis.md)

---

## Goals

By end of Phase 1, demonstrate:

1. **UC1 OPD HT/DM follow-up demo:** 43Files import overnight → Smart-on-FHIR app launched from OpenEMR shows BP/HbA1c trends + active problems + medications, all sourced from `mimir-fhir` R5 canonical store
2. **UC3 paediatric immunization demo:** EPI table → Immunization resource end-to-end; vaccine-schedule logic computes next due
3. **MOPH-PC1 conformance suite:** all 78 elements round-trip green; R4↔R5 translator covers all renames + polymorphism merges; `MedicationStatement.adherence` preserved on R5, dropped-with-extension on R4 emit
4. **HOSxP integration proof:** 43Files-to-FHIR adapter runs against one anonymized HOSxP test database without error

## Non-Goals (Phase 1 — explicit cuts to prevent scope creep)

Do NOT implement in Phase 1 (defer to Phase 2-5):

- All Layer 2 clinical modules (eir-ddx, order-sets, MAR, sbar-handoff, acls-timer, or-checklist, vaccine-schedule full UI, med-reconciliation, care-pathway executor) — Phase 2+
- Lab HL7 v2 ingest — Phase 3
- FHIR Subscription / FHIRcast / `$export` Bulk Data — never (out of scope)
- FHIR Operations beyond what REST CRUD needs — never
- Multi-tenant cloud deployment — never (per [ADR-009](../decisions/ADR-009-single-tenant-mac-mini-deployment.md))
- Full FHIR search semantics (`_include`, `_revinclude`, chained, composite) — Phase 2+
- Write API for resources beyond Patient/Encounter/Observation — Phase 2 (read-first per ADR-012 D5)
- AuditEvent / Provenance FHIR resources — never (Tyr SIEM owns audit)
- Visual diff UI for R4 vs R5 — never (CLI tool sufficient)

---

## Pre-Conditions (must be true before Sprint 1)

Verified during Sprint 0 (pre-flight). Sprint 1 cannot start until all pass.

| # | Pre-condition | Source / verification |
|---|---|---|
| P1 | S1 Go/No-Go passed (2026-06-12) | Mimir eval Hit Rate@3 ≥75% |
| P2 | Insurance Launch S52-54 production stable | No P1 incidents 4 consecutive weeks |
| P3 | Living Evidence S55-58 shipped | Mimir Guideline Lineage + mimir-well + mimir-curator merged + smoke-test green |
| P4 | Full T7 backup verified (per [[asgard_full_backup_procedure]]) | `scripts/backup-full-k8s.sh` run, MANIFEST + gzip integrity OK |
| P5 | Anonymized HOSxP test dump available | At least one real HOSxP MariaDB dump, PII-stripped, ~1000 patients, ~10000 encounters |
| P6 | OpenEMR test instance running on dev box | `docker compose up openemr` in Asgard dev env |
| P7 | Mac mini headroom check | `sudo purge` then ≥30GB free RAM before heavy sprint work (per [[mac_mini_specs]]) |
| P8 | Cargo workspace structure confirmed | `Mimir/Cargo.toml` workspace can accept `mimir-fhir` member |
| P9 | TH Core profile JSON available | Download from fhir.moph.go.th — Patient, Encounter, Observation, etc. |
| P10 | MOPH-PC1 78-element corpus drafted | Sample data ≥5 patients covering all 78 elements (manual or scripted) |

---

## Sprint Plan (10 Sprints × 2 weeks)

### Sprint 0 — Pre-Flight & Test Corpus (Week 0, ~5 days)

**Goal:** Verify all pre-conditions; collect / generate test data; scaffold project.

**Tasks:**

- [ ] Run all 10 pre-condition checks; document gaps; create issues for any fail
- [ ] Backup verification: T7 Shield mount, run `backup-full-k8s.sh`, verify MANIFEST
- [ ] Acquire / generate test data:
  - Anonymized HOSxP dump (43Files MariaDB tables: PERSON, SERVICE, ADMISSION, NCDSCREEN, DIAGNOSIS_OPD/IPD, DRUG_OPD/IPD, PROCEDURE_OPD/IPD, LABFU, EPI, DRUGALLERGY)
  - OpenEMR test instance with seed data (Patient, Encounter, Observation, MedicationRequest)
  - HAPI FHIR R4 sandbox URL or local R4 test corpus
- [ ] Create 78-element MOPH-PC1 conformance corpus (5 synthetic patients, manual JSON for now)
- [ ] Scaffold Cargo workspace member `mimir-fhir/` under `Mimir/`
- [ ] CI: GitHub Actions for `mimir-fhir` (cargo check, clippy, test)
- [ ] Branch `feat/mimir-fhir-phase-1` from `main`

**Acceptance:**
- All 10 pre-conditions green or explicit waiver documented
- `cargo check` on empty `mimir-fhir` crate passes
- Test corpus committed to `mimir-fhir/tests/moph_pc1/fixtures/`

**Risks:**
- HOSxP dump availability — if blocked, must generate synthetic 43Files dump from spec
- TH Core profile JSON drift between download and ADR-006 assumptions

**Backup gate:** ☑ Required (T7 Shield full backup before any state mutation in Sprint 7+)

---

### Sprint 1 — Datatypes & Type-System Foundation (~10 days)

**Goal:** All FHIR R5 primitive + complex datatypes implemented in Rust with `schemars` + serde + tests.

**Tasks:**

- [ ] Primitive datatypes (typed newtypes): `Id`, `Code`, `Canonical`, `Uri`, `Url`, `Markdown`, `DateTime`, `Date`, `Time`, `Instant`, `Base64Binary`, `Decimal`, `PositiveInt`, `UnsignedInt`
- [ ] Complex datatypes:
  - `Identifier` (with Thai citizen ID slice support stubbed)
  - `CodeableConcept`, `Coding`
  - `Reference` (literal + logical)
  - `HumanName` (with `_language` extension for Thai/English bilingual)
  - `Address` (with Thai address extension scaffolding: province/district/sub-district)
  - `ContactPoint`, `Period`, `Quantity`, `Money`, `Range`, `Ratio`, `Annotation`
  - `Meta` (no version_id stored — derived on emit per ADR-006 D2)
  - `Extension`, `Narrative`
- [ ] `schemars::JsonSchema` derive on every type
- [ ] FHIR `_language` extension helper for i18n per ADR-006 D5
- [ ] Cardinality annotations via `#[schemars(length(min = N))]` for 1..* fields
- [ ] Tests: serialize/deserialize round-trip for each datatype against FHIR R5 reference JSON

**Acceptance:**
- All datatypes compile + pass round-trip tests
- `cargo test -p mimir-fhir` green
- JSON Schema generated to `target/schemas/datatypes/*.json`

**Dependencies on prior sprints:** Sprint 0

**Risks:**
- Decimal precision: FHIR allows arbitrary precision; Rust `f64` insufficient. Use `rust_decimal::Decimal` or `bigdecimal::BigDecimal`.

**Backup gate:** ☐ Not required (no state mutation)

---

### Sprint 2 — Patient + Encounter + R4↔R5 Translator Scaffold (~10 days)

**Goal:** First two clinical resources implemented; R4↔R5 translator module exists for these two resources.

> **2026-05-27 update:** R4↔R5 translator framework now specified in detail by [ADR-017 — R4↔R5 Translation Framework](../decisions/ADR-017-fhir-r4r5-translation-framework.md). Sprint 2 task list below remains correct; the translator scaffold follows ADR-017's 8-category × 4-severity-level discipline with compile-time macro guard and Tyr audit on lossy events.

**Tasks:**

- [ ] **Patient resource** (R5):
  - Full canonical struct + serde + schemars
  - Thai citizen ID identifier slice (per MOPH-PC1 Patient profile)
  - Thai address extension (province, district, sub-district)
  - Bilingual HumanName (Thai + Latin)
  - `External*` newtype for lenient inbound parsing per ADR-006 D4
- [ ] **Encounter resource** (R5):
  - `actualPeriod` (R5; R4 was `period`)
  - `admission.dischargeDisposition` (R5; R4 was `hospitalization.dischargeDisposition`)
  - Diagnosis reference
- [ ] **R4↔R5 translator module** scaffold:
  - `mimir-fhir/src/translate/r4_to_r5/` directory
  - Patient translator (mostly pass-through)
  - Encounter translator (period ↔ actualPeriod rename; hospitalization ↔ admission rename)
- [ ] Round-trip tests:
  - R5 → JSON → R5 identity
  - R4 → R5 → R4 identity for lossless subset
- [ ] Profile validator stubs (TH Core Patient + MoPH-PC Patient; Encounter)

**Acceptance:**
- Patient + Encounter compile + round-trip
- R4↔R5 translator handles Patient (no-op) and Encounter (renames) correctly
- MOPH-PC1 corpus rows 1-9 (Patient) and 34-39 (Encounter) pass conformance

**Dependencies:** Sprint 1

**Risks:**
- TH Core Patient profile may have additional Thai-specific slices we have not catalogued — verify against published profile JSON
- Encounter.location reference target (Location resource) not yet implemented — stub with `Reference` only

**Backup gate:** ☐ Not required

---

### Sprint 3 — Observation Resource + 8 Sub-Profile Builders (~10 days)

**Goal:** Observation resource + all 8 specialized typed builders per ADR-006 Amendment 1.

**Tasks:**

- [ ] Base `Observation` resource (R5)
- [ ] 8 typed sub-profile builders:
  - [ ] `VitalSignBuilder` — SBP/DBP (component pattern), HR, RR, Temp, BW, HT, SpO2
  - [ ] `LabResultBuilder` — code, valueQuantity, specimen reference, status, unit, referenceRange, interpretation
  - [ ] `OccupationBuilder` — Thai occupation code system
  - [ ] `PregnancyStatusBuilder`
  - [ ] `AlcoholStatusBuilder`
  - [ ] `SmokingStatusBuilder`
  - [ ] `ImagingResultBuilder` — valueString for interpretation text
  - [ ] `GenericObservationBuilder` — fallback for history/physical exam/clinical test
- [ ] LOINC code system bindings (compile-time const for vital signs: 8480-6, 8462-4, 8867-4, 9279-1, 8310-5, 8302-2, 29463-7, 2708-6)
- [ ] Type-safe builders that reject mis-matched LOINC codes at compile time
- [ ] Tests per sub-profile against MOPH-PC1 corpus IDs 10-18, 29-31, 33, 47-53, 55-61

**Acceptance:**
- All 8 sub-profiles compile + pass tests
- VitalSignBuilder rejects non-vital LOINC (e.g., lab LOINC) at compile time
- MOPH-PC1 corpus rows 10-18 + 29-31 + 33 + 47-53 + 55-61 (vital signs + clinical info + imaging result + health status + lab) pass conformance

**Dependencies:** Sprint 2

**Risks:**
- Type-state pattern in Rust for sub-profile dispatch may be over-engineered — start simple (validate at runtime), add compile-time gating only if tests show drift
- BP component pattern (SBP + DBP in single Observation) needs careful struct design

**Backup gate:** ☐ Not required

---

### Sprint 4 — Clinical Resources Set (~11 days)

**Goal:** Condition, MedicationRequest, MedicationStatement, Procedure, AllergyIntolerance, DiagnosticReport, DocumentReference, **Composition** implemented.

> Sprint 4 was originally scoped at ~10 days / 7 resources. Per [ADR-015](../decisions/ADR-015-add-composition-and-uc2-patient-summary.md) (2026-05-26), `Composition` (R5) is added as the 21st canonical resource to support UC2 Cross-Encounter Patient Summary in Sprint 10. Budget +1 day.

**Tasks:**

- [ ] **Condition** (R5)
  - `code` (ICD-10-TM, SNOMED bindings)
  - `recordedDate`, `abatementDateTime`
- [ ] **MedicationRequest** (R5)
  - `medication` as **single CodeableReference** (NOT R4 polymorphism)
  - TMT (Thai Medication Terminology) code system binding
  - `dosageInstruction.doseAndRate.doseQuantity`
  - `reason` as CodeableReference
- [ ] **MedicationStatement** (R5)
  - **`adherence` field (R5-only)** — first-class
  - `dosage`
- [ ] **Procedure** (R5)
  - `code` (ICD-9-CM-Vol3, SNOMED)
  - `occurrenceDateTime`
  - `reason` as CodeableReference
- [ ] **AllergyIntolerance** (R5)
  - `code`, `category` (medication/food/environment/biologic)
  - `reaction.manifestation` (SNOMED)
- [ ] **DiagnosticReport** (R5)
- [ ] **DocumentReference** (R5)
- [ ] **Composition** (R5) — *added 2026-05-26 per ADR-015*
  - `type` (LOINC binding; UC2 uses `60591-5` "Patient summary Document")
  - `status` (`preliminary` / `final` / `amended` / `entered-in-error`)
  - `subject` (required, `Patient` reference)
  - `date`, `author[]` (`Practitioner` OR `Device` — LLM-authored = `Device(asgard-eir-summary-v{N})`)
  - `title`, `section[]` with `section.text.div` (XHTML narrative) + `section.entry[]` (references to leaf resources in same Bundle)
  - Helper builder: `Composition::asgard_patient_summary(subject, author, sections)`
  - R4↔R5 translator: identity transform (no breaking changes for fields in UC2 scope)
- [ ] R4↔R5 translator rules for:
  - MedicationRequest.medication: R4 `medicationCodeableConcept`/`medicationReference` → R5 `medication` CodeableReference
  - MedicationRequest.reason / Procedure.reason: R4 `reasonCode`/`reasonReference` → R5 `reason` CodeableReference
  - MedicationStatement.adherence: R5 → R4 extension `http://asgard.local/fhir/r5-only/medication-adherence`; R4 → R5 read extension back
  - Composition: identity (R4≡R5 for UC2 fields)

**Acceptance:**
- All 8 resources compile + round-trip (7 clinical + Composition)
- R4↔R5 translator handles polymorphism merges + adherence extension correctly
- MOPH-PC1 corpus rows 19-28, 66-78 (allergies, documents, meds, problems, procedures) pass
- Composition round-trips a fixture with 6 sections + leaf-resource entry references

**Dependencies:** Sprint 2 (Patient + Encounter references), Sprint 3 (Observation for Composition entries)

**Risks:**
- TMT code system not bundled in repo — needs reference table; coordinate with Mimir KB on T7 ([[mimir_data_on_t7]])
- R5 CodeableReference is a new type combining `concept` + `reference` — may need helper
- Composition.section recursion (sections containing sub-sections) — UC2 scope uses flat 6-section structure, defer recursive support to Phase 2

**Backup gate:** ☐ Not required

---

### Sprint 5 — Facility, Coverage, Lab Specimen, Imaging, Device, Immunization (~10 days)

**Goal:** Remaining 8 resources: Practitioner, Organization, Location, Coverage, Claim, ClaimResponse, Specimen, ImagingStudy, Immunization, Device.

**Tasks:**

- [ ] **Practitioner** (R5)
- [ ] **Organization** (R5) — MoPH-PC Organization: Provider profile
- [ ] **Location** (R5) — new in ADR-006 A1
- [ ] **Coverage** (R5)
- [ ] **Claim** (R5) — for asgard_insurance tenant
- [ ] **ClaimResponse** (R5) — for asgard_insurance tenant
- [ ] **Specimen** (R5) — new in ADR-006 A1; supports lab Observation
- [ ] **ImagingStudy** (R5) — new in ADR-006 A1; image interpretation text uses Observation
- [ ] **Immunization** (R5) — new in ADR-006 A1; `vaccineCode` (NOT `valueCodeableConcept` per mapping doc note)
- [ ] **Device** (R5) — new in ADR-006 A1; `udiCarrier`
- [ ] `BundleEntry` closed enum with all 20 variants (per ADR-006 D1 + A1)
- [ ] Tests against MOPH-PC1 corpus rows 32, 40-46, 54, 62-65

**Acceptance:**
- All 20 resources implemented; `BundleEntry` enum complete
- MOPH-PC1 corpus 78/78 elements pass type-level conformance (profile validation still partial)
- `cargo build` clean

**Dependencies:** Sprint 4

**Risks:**
- Claim / ClaimResponse complexity for insurance use case may bleed into asgard_insurance work — keep Phase 1 implementation minimal (read-only stub)

**Backup gate:** ☐ Not required

---

### Sprint 6 — REST API + Persistence Layer (~10 days)

**Goal:** Read-only FHIR R5 REST endpoint for Patient/Encounter/Observation; persistence to MariaDB; Tyr audit integration for meta derivation.

**Tasks:**

- [ ] **MariaDB schema** for `mimir-fhir` resources:
  - `fhir_resource` table: id (ULID), tenant_id, resource_type, version (latest only — history via Tyr), content JSON, created_at, updated_at
  - Index by (tenant_id, resource_type, id), (tenant_id, resource_type, updated_at)
  - **Backup before applying schema migration** (per [[feedback_backup_before_changes]])
- [ ] **Migration script** with rollback support
- [ ] **Persistence layer** in Rust (sqlx or sea-orm):
  - `FhirStore::put(resource)` — upsert + Tyr audit emit
  - `FhirStore::get(resource_type, id)` — read latest
  - `FhirStore::list(resource_type, filters)` — Phase 1 minimal: by patient, by date range, by code
- [ ] **Tyr audit integration:**
  - Every write emits Tyr event with `(tenant_id, resource_type, resource_id, before_hash, after_hash, actor)`
  - `meta.versionId` derived from latest Tyr event_id on read
  - `meta.lastUpdated` derived from latest Tyr event ts on read
- [ ] **REST endpoint** via axum:
  - `GET /fhir/r5/{resource_type}/{id}` — read
  - `GET /fhir/r5/{resource_type}` — search (minimal: `?patient=X&date=geY`)
  - **Content negotiation** for R4 emit: `Accept: application/fhir+json;fhirVersion=4.0`
- [ ] **Write endpoint** for Patient/Encounter/Observation only (rest read-only Phase 1)
- [ ] Integration test: PUT then GET round-trip via REST

**Acceptance:**
- `GET /fhir/r5/Patient/A12345` returns valid R5 Patient
- `Accept: ...fhirVersion=4.0` header returns valid R4 Patient
- Tyr audit chain contains write event for each PUT
- `meta.versionId` derived correctly from Tyr

**Dependencies:** Sprint 2 (Patient/Encounter), Sprint 3 (Observation)

**Risks:**
- Tyr availability — if Tyr scaled down ([[tyr_wazuh_scaled_down]]), audit emit must use LocalDbSink fallback per ADR-002
- Schema migration on production-like DB — must run restore drill in scratch namespace first

**Backup gate:** ☑ **REQUIRED** before MariaDB schema migration. Run `scripts/backup-full-k8s.sh` to T7 Shield. Verify MANIFEST + gzip integrity. Document tag `pre-mimir-fhir-schema`.

---

### Sprint 7 — Profile Validators (TH Core + MoPH-PC) (~8 days)

**Goal:** Profile validators implement tightest-binding-wins per MOPH-PC1 mapping doc Section "Profile Layers".

> **2026-05-27 update:** Cascade order revised by [ADR-016 — Asgard FHIR Profile Family](../decisions/ADR-016-asgard-fhir-profile-family.md) and [ADR-019 — Profile Validation Tightest-Binding-Wins](../decisions/ADR-019-fhir-profile-validation-tightest-binding-wins.md). Cascade is now **symmetric across Base R5 + TH Core (when adopted) + Asgard FHIR Profile** — MoPH-PC1 is informative-only and does NOT participate in validation. Asgard's profile does NOT authoritatively override; tightest binding wins uniformly. Irreconcilable bindings produce BUILD ERROR (not runtime warning). Validators are compile-time generated. See ADR-019 for the 6-dimension merge algorithm + performance target (≥1k r/s).

**Tasks:**

- [ ] **TH Core profile validators** for each resource:
  - Required slices (e.g., Patient.identifier with Thai citizen ID)
  - Required extensions (Thai address, bilingual name)
  - Cardinality constraints
  - Value set bindings (e.g., gender, country code TH)
- [ ] **MoPH-PC profile validators** (tighter superset of TH Core):
  - Primary care specific constraints
  - Required Observation profile bindings per LOINC vital signs subset
- [ ] **Tightest-binding-wins logic:**
  - `validate(resource)` walks: MoPH-PC → TH Core → FHIR base
  - Returns first-match validation result
- [ ] **Validation API:**
  - `validator.validate(resource, profile_hint?)` → `ValidationResult { errors, warnings }`
- [ ] **Conformance test corpus run:**
  - All 78 MOPH-PC1 corpus elements
  - Both happy path (valid) + 10 negative path tests (intentionally invalid for each profile)

**Acceptance:**
- 78/78 MOPH-PC1 corpus elements pass tightest-binding validation
- 10/10 negative tests catch the intended profile violation
- Validation errors include FHIR-spec OperationOutcome shape

**Dependencies:** Sprints 1-5 (all resources)

**Risks:**
- TH Core profiles published by MOPH may evolve; pin to a specific snapshot date in commit history
- Profile JSON parsing into Rust validator — may need code-gen tool (defer to Phase 2 if hand-written is faster)

**Backup gate:** ☐ Not required (read-only validation)

---

### Sprint 8 — 43Files-to-FHIR Adapter (~14 days, biggest sprint)

**Goal:** Bidirectional adapter between MOPH 43-Files MariaDB schema (HOSxP/OpenEMR backend) and FHIR R5 canonical store.

> **2026-05-27 update:** Adapter architecture now specified by [ADR-020 — 43Files HOSxP→FHIR Adapter](../decisions/ADR-020-43files-hosxp-fhir-adapter.md) + companion [mapping matrix](../architecture/43files-fhir-mapping-matrix.md). Key refinements that supersede the in-plan task list below: (1) crate is **separate** `mimir-43files-adapter` (not `mimir-fhir/src/adapters/`), (2) sync strategy = polling default + CDC opt-in (binlog), (3) identity = stable UUID v5(hospital_id, CID/HN-fallback), (4) Phase 1 scope = 12 priority tables → 11 resources (CHARGE/DEATH/SURGERY deferred), (5) TIS-620 + Buddhist year auto-normalize at boundary, (6) every resource passes ADR-019 validators pre-store, (7) Tyr `fhir.ingest.*` quality events. Sprint duration is 4 weeks (~20 days) not 14.

**Tasks:**

- [ ] **Adapter module structure** `mimir-fhir/src/adapters/forty_three_files/`:
  - `mod.rs` — entry point + cron runner
  - `person.rs` — PERSON table → Patient
  - `service.rs` — SERVICE table → Encounter (OPD) + Observation (vitals subset)
  - `admission.rs` — ADMISSION table → Encounter (IPD)
  - `ncdscreen.rs` — NCDSCREEN → Observation (BP, BW, HT, smoking, alcohol)
  - `diagnosis.rs` — DIAGNOSIS_OPD/IPD → Condition + Encounter.diagnosis
  - `drug.rs` — DRUG_OPD/IPD → MedicationRequest
  - `procedure.rs` — PROCEDURE_OPD/IPD → Procedure
  - `labfu.rs` — LABFU → Observation (lab sub-profile) + Specimen
  - `epi.rs` — EPI → Immunization
  - `drugallergy.rs` — DRUGALLERGY → AllergyIntolerance
  - `card.rs` — CARD → Coverage
- [ ] **Per-table adapter** has:
  - SQL query against source MariaDB
  - Row → FHIR resource mapping function
  - Idempotency: hash of source row → upsert (avoid duplicate on re-run)
  - Audit emit to Tyr per ingested row
- [ ] **Cron runner** integrated with Bifrost cron ([[bifrost_cron_monitor]]):
  - Nightly full sync (configurable window)
  - Incremental delta sync (by row updated_at)
- [ ] **Idempotency strategy:**
  - 43Files source row hash (sha256 of canonical row JSON) stored in `fhir_resource.metadata`
  - Re-run with same source hash = no-op
- [ ] **Test against anonymized HOSxP dump:**
  - Ingest 1000 patients × ~10000 encounters
  - Verify no errors, no duplicates on second run
  - Spot-check 20 random patients for FHIR conformance

**Acceptance:**
- All 10 gold-value tables (PERSON, SERVICE, ADMISSION, NCDSCREEN, DIAGNOSIS_OPD/IPD, DRUG_OPD/IPD, PROCEDURE_OPD/IPD, LABFU, EPI, DRUGALLERGY, CARD) adapt to correct FHIR R5 resource
- Idempotent: 2x run = same FHIR state, no duplicates
- Performance: 1000 patients ingest in <5 minutes on Mac mini
- 20 spot-check patients pass MOPH-PC1 conformance after ingest

**Dependencies:** Sprints 1-7

**Risks:**
- **High risk sprint.** Real HOSxP schema may have quirks not in MOPH-PC1 spec (custom columns, version-specific differences). Plan for 20-30% schedule slip.
- HOSxP table naming may differ by version — test against ≥2 HOSxP versions if possible
- Performance: 1000 patients may be slow if not batched correctly

**Backup gate:** ☑ **REQUIRED** before first full sync. Backup `fhir_resource` table (likely empty pre-sprint) AND source HOSxP DB (read-only but want consistent snapshot). Document tag `pre-43files-ingest`.

---

### Sprint 9 — Smart-on-FHIR Launch + OpenEMR Integration (~10 days)

> **2026-05-27 update:** SMART on FHIR 2.0 architecture now specified by [ADR-022 — SMART on FHIR 2.0 Launch and Authorization](../decisions/ADR-022-smart-on-fhir-launch.md). Key locks: (1) 4 client types — EHR launch, standalone, CDS Hooks (separate JWT), Backend Services (private_key_jwt for `mimir-43files-adapter` + `eir-cqm`); (2) hybrid 5-min fat JWT + refresh; (3) static client registration (3 pre-registered: asgard-cds, asgard-eir-ui, asgard-admin); (4) patient context = signed JWT claim, NOT header; (5) Yggdrasil extended (not replaced); (6) discovery endpoint on mimir-fhir at `/fhir/R5/.well-known/smart-configuration`. Sprint expanded from 10 to ~20 days to include standalone launch + Backend Services flows.

**Goal:** Smart-on-FHIR app can launch from OpenEMR (or HAPI sandbox if OpenEMR Smart-on-FHIR support is partial), receive launch context, fetch FHIR resources from `mimir-fhir`.

**Tasks:**

- [ ] **Smart-on-FHIR launcher endpoint:**
  - `/smart/launch/{app_id}` — initiates OAuth2 launch flow
  - `/smart/authorize`, `/smart/token` — minimal OAuth2 implementation (or proxy to Yggdrasil/Zitadel per [[asgard_jwt_auth_pattern]])
  - `/.well-known/smart-configuration` — Smart-on-FHIR discovery document
- [ ] **OpenEMR plugin / configuration:**
  - Document Smart-on-FHIR app registration in OpenEMR
  - Provide launch URL configuration
  - **If OpenEMR Smart-on-FHIR is incomplete:** build minimal launcher app that mimics the launch context (patient + encounter context tokens)
- [ ] **Demo Smart-on-FHIR client app** (React or SolidJS, served from `mimir-fhir`):
  - Reads launch context (patient + encounter id)
  - Fetches Patient, Observation (vitals + lab), Condition, MedicationRequest from `mimir-fhir` REST
  - Renders simple "patient summary" view — enough to validate launch flow end-to-end
- [ ] **HAPI sandbox fallback:**
  - If OpenEMR proves unworkable, demo against HAPI Smart-on-FHIR sandbox using R4 emit path
- [ ] Tests: end-to-end launch from OpenEMR (or HAPI) → token → fetch resources → render

**Acceptance:**
- Click "Asgard Decision Support" button in OpenEMR (or sandbox equivalent) → launches app → app fetches patient FHIR resources from `mimir-fhir` → renders summary
- OAuth2 launch flow secure (token introspection, scope enforcement)
- R4-emit path verified end-to-end (R4 client launches against R5 store)

**Dependencies:** Sprint 6 (REST endpoint), Sprint 8 (data in store)

**Risks:**
- OpenEMR Smart-on-FHIR support is incomplete in some versions — fallback to custom launcher
- HOSxP has no native Smart-on-FHIR launcher (open question 10.3 in Confidential summary) — out of scope for Phase 1; document workaround

**Backup gate:** ☐ Not required (no destructive state mutation)

---

### Sprint 10 — UC1 + UC2 + UC3 Demo + Phase 1 Acceptance (~12 days)

**Goal:** Three minimum-viable demos working end-to-end; Phase 1 acceptance criteria green; demo deck ready.

> Sprint 10 was originally scoped at ~10 days / 2 demos (UC1 + UC3). Per [ADR-015](../decisions/ADR-015-add-composition-and-uc2-patient-summary.md) (2026-05-26), UC2 Cross-Encounter Patient Summary is added as a third demo. Budget +2 days for UC2 demo prep.

**Tasks:**

- [ ] **UC1 OPD HT/DM follow-up demo:**
  - Pre-populate 43Files test DB with ~5 representative HT/DM patients
  - Run nightly adapter
  - Smart-on-FHIR launch from OpenEMR opens app showing:
    - Patient demographics
    - BP trend (last 4 visits) from Observation
    - HbA1c trend from LABFU Observation
    - Active problems (Condition)
    - Active medications (MedicationRequest)
- [ ] **UC2 Cross-Encounter Patient Summary demo:** *(added 2026-05-26 per ADR-015)*
  - Pre-populate 43Files test DB with 3 patients of varying complexity:
    - **P1 simple** — 1 chronic condition (HT), 1-2 medications, ≤5 encounters
    - **P2 chronic-complex** — 4+ chronic conditions (HT+DM+dyslipidemia+CKD3), 6-10 active meds, ≥20 encounters across 3 years
    - **P3 polypharmacy** — 8+ active meds with at least 2 known drug-drug interactions, 1+ adherence concern (per `MedicationStatement.adherence` R5 field)
  - Insert `eir-summary` agent row in `agent_configs` (asgard_medical tenant, model `gemma-4-26b`, tool allowlist `["openemr_patient_bundle_fetch"]`)
  - Smart-on-FHIR launch → eir-summary fetches Bundle via mimir-fhir REST → LLM generates Composition JSON → validates against `Composition-asgard-patient-summary` profile (Sprint 7) → app renders with per-section navigation
  - Acceptance criteria:
    - All 3 demo patients produce valid `Composition` (profile-conformant)
    - Each Composition has all 6 required sections (Problems, Medications, Allergies, Results, Vital signs, Plan)
    - `section.entry[]` references resolve to leaf resources in mimir-fhir store
    - `author = Device(asgard-eir-summary-v{N})` with `status = preliminary`
    - Tyr audit chain records: input resource hashes, model + version, output Composition hash, generation latency
    - p50 generation latency < 30 s on Mac mini for P2 patient (chronic-complex baseline)
- [ ] **UC3 paediatric immunization demo:**
  - Pre-populate 43Files EPI table with ~5 children at different ages
  - Run nightly adapter
  - Smart-on-FHIR app shows:
    - Immunization history (from Immunization resources)
    - Next-due vaccine per Thai MOPH EPI 2024 schedule (simple JS logic — NOT full vaccine-schedule Layer 2 module; that is Phase 2)
- [ ] **MOPH-PC1 78-element conformance suite full run:**
  - All 78 elements round-trip green
  - R4 emit + R4 → R5 → R4 lossless subset round-trip green
  - MedicationStatement.adherence preserved on R5, extension on R4
- [ ] **Demo deck** (10-15 slides):
  - Before/after for UC1 + UC3
  - Architecture diagram (3-layer)
  - "Why not just HOSxP" + "why not full EHR" positioning
  - Phase 2-5 roadmap
- [ ] **Phase 1 retro:** what worked, what slipped, what to change for Phase 2

**Acceptance:**
- All 4 acceptance criteria in [Goals](#goals) section green
- Demo recordable (screen capture) for prospect / partner conversations
- Phase 1 retro doc filed in `docs/sprints/`

**Dependencies:** All prior sprints

**Risks:**
- Time pressure to integrate everything — leave 3 days buffer
- Demo data realism — synthetic data may not surface real-world issues; flag for Phase 2 with real customer pilot data

**Backup gate:** ☑ Full backup of all `mimir-fhir` state before demo recording (in case of accidental data corruption during demo prep).

---

## Milestones

| Milestone | After Sprint | Date (est.) | Deliverable |
|---|---|---|---|
| **M1: Type system v0** | 5 | ~Week 11 | All 20 resources + datatypes + BundleEntry enum compile, round-trip green |
| **M2: REST + Persistence live** | 6 | ~Week 13 | `mimir-fhir` running as service; can PUT/GET via REST |
| **M3: Profile conformance** | 7 | ~Week 15 | 78-element MOPH-PC1 corpus passes tightest-binding validation |
| **M4: HOSxP integration proven** | 8 | ~Week 19 | 43Files adapter ingests anonymized HOSxP dump green |
| **M5: Smart-on-FHIR launch proven** | 9 | ~Week 21 | App launches from OpenEMR / sandbox, fetches FHIR |
| **M6: Phase 1 demo ready** | 10 | ~Week 23 | UC1 + UC3 demos recorded; ready for prospect conversations |

---

## Test Strategy

Per [[development_practices]] — TDD throughout.

### Test Levels

| Level | Tool | What | When |
|---|---|---|---|
| Unit | `cargo test` | Per-type serialization, validation logic, translator rules | Every sprint, every commit |
| Integration | `cargo test --test integration` | REST endpoint, persistence, adapter pipeline | Sprints 6-10 |
| Conformance | Custom harness | 78-element MOPH-PC1 corpus | Sprint 7 onward, every commit to main |
| E2E | Playwright or Cypress | Smart-on-FHIR launch → app → fetch → render | Sprint 9-10 |
| Regression | `mimir/eval/` ([[primekg_resolver_regression]] pattern) | Compare adapter output across versions | Sprint 8 onward |

### Test Data Sources

1. **MOPH-PC1 synthetic corpus** (5 patients × 78 elements) — manually crafted, committed to repo
2. **Anonymized HOSxP dump** — PII-stripped real-world data, NOT committed (referenced via env var path)
3. **HAPI FHIR R4 sandbox** — external endpoint for R4 round-trip tests
4. **Real-world adversarial samples** (Sprint 8+) — quirks discovered during HOSxP integration, codified as regression tests

### Coverage Targets

- Line coverage ≥ 80% for `mimir-fhir/src/`
- Branch coverage ≥ 70%
- 100% of MOPH-PC1 78 elements have a passing test

---

## Backup Strategy (per [[feedback_backup_before_changes]])

**Hard rule:** every sprint that mutates persistent state lists an explicit backup step. No implicit/assumed backups.

| Sprint | Mutates state? | Backup gate |
|---|---|---|
| 0 | ☑ (pre-flight; create test data dirs) | T7 full backup `pre-mimir-fhir-phase-1` |
| 1-5 | ☐ (code only, no DB) | Not required |
| 6 | ☑ (MariaDB schema migration) | T7 full backup `pre-mimir-fhir-schema`; verify restore drill in scratch namespace |
| 7 | ☐ (read-only validation) | Not required |
| 8 | ☑ (first full 43Files ingest) | T7 backup of `fhir_resource` table + HOSxP source DB; tag `pre-43files-ingest` |
| 9 | ☐ (OAuth2 + REST only) | Not required |
| 10 | ☑ (demo data prep) | Full backup before demo recording |

Restore drill script `scripts/restore-from-backup.sh` must exist before Sprint 6 (carried over from `mimir-well` Sprint 56 per [[sprint56_schema_early_apply]]).

---

## Deployment Strategy

Per [[asgard_orbstack_k8s]] + [[asgard_local_deployment_strategy]]:

1. **Dev:** local Cargo + sqlite or local MariaDB; iterate fast
2. **Staging:** deploy to OrbStack K8s on dev Mac mini; use `./scripts/k3s-deploy.sh` for `mimir-fhir` service
3. **Production:** customer Mac mini (Phase B hospital pilot); SemVer tag (v0.1.0 → v0.x.x during Phase 1) per [[semver_release_process]]

**Service shape:**
- New K8s Deployment `mimir-fhir` in `asgard` namespace
- NodePort or ClusterIP behind Heimdall gateway
- Configured via Vault (per Asgard convention)
- Health/ready probes
- Prometheus metrics endpoint per [[bifrost_cron_monitor]] pattern

**Image:** local Docker build per [[asgard_local_deployment_strategy]] (NOT GitHub CI initially); push to ghcr only after v0.x.x stable.

---

## Risk Register (Sprint-Level)

| Risk | Sprint | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| HOSxP test dump unavailable | 0 | Medium | High | Generate synthetic dump from spec |
| TH Core profile JSON drift | 2 | Medium | Medium | Pin to snapshot date, document drift |
| Decimal precision issues in Rust | 1 | Low | Medium | Use `rust_decimal::Decimal` |
| Type-state pattern over-engineered | 3 | Medium | Low | Start with runtime validation, add compile-time only on demand |
| TMT code table unavailable | 4 | Low | Medium | Coordinate with Mimir KB on T7 Shield |
| Tyr scaled-down breaks audit emit | 6 | Medium | Medium | Use LocalDbSink fallback per ADR-002 |
| HOSxP schema quirks not in spec | 8 | High | High | 20-30% schedule buffer; document quirks as regression tests |
| OpenEMR Smart-on-FHIR incomplete | 9 | High | Medium | Fallback to HAPI sandbox or custom launcher |
| Demo data not realistic enough | 10 | High | Low | Flag for Phase 2 real-pilot data |
| Founder bandwidth (solo dev) | All | High | High | Strict scope discipline; defer to Phase 2 anything not in Goals section |
| Mac mini memory pressure during heavy sprint | All | Medium | Medium | `sudo purge` before; serialize ops per [[feedback_mac_mini_memory_pressure]] |

---

## Team / Resources Needed

**Minimum (solo dev):**
- Founder full-time on `mimir-fhir` for 20 weeks
- Clinical advisor (~4 hours/week) for spec validation + UC1/UC3 demo review
- 1 anonymized HOSxP dump (from friendly hospital / partner)
- OpenEMR test instance
- T7 Shield (already in inventory)

**Nice to have (~2× speed):**
- +1 Rust engineer for Sprints 1-5 (type system foundation)
- +1 frontend engineer for Sprint 9-10 (Smart-on-FHIR demo app)
- Clinical advisor full-time for Sprint 10 demo prep

**Defer to Phase 2:**
- Sales / CSM hires (Phase B kickoff, not Phase 1 build)
- Dedicated QA — TDD coverage from sprints is sufficient for v0

---

## What to Do NOW (Pre-Phase-1 — before S58 wraps)

These can run in parallel with current S55-58 work without blocking:

- [ ] **Confirm pre-conditions P1-P3** track to Sept 2026 timeline; if S58 slips, Phase 1 slips
- [ ] **Acquire anonymized HOSxP dump** from a friendly hospital partner (likely sleep clinic per Asgard origin story, or Beryl8/Prudential network)
- [ ] **Download TH Core profile JSON snapshot** from fhir.moph.go.th and commit to `mimir-fhir/profiles/`
- [ ] **Verify OpenEMR Smart-on-FHIR support level** — install on dev box and test the launch flow against HAPI sandbox
- [ ] **Build MOPH-PC1 synthetic corpus** (5 patients × 78 elements) — can start now since spec is locked
- [ ] **Spike: fhir-rs crate evaluation** — clone fhir-rs / fhir-sdk-rs, evaluate if any of them is usable as a starting point or if we go from scratch
- [ ] **Restore drill script** (`scripts/restore-from-backup.sh`) — if not built yet during Sprint 56 work, add to Sprint 0
- [ ] **Confirm Beryl8/Prudential POC** doesn't have FHIR data plane dependency that bleeds into Phase 1 timeline

---

## Open Questions (must close before Sprint 1)

| # | Question | Owner | Target close |
|---|---|---|---|
| 1 | `mimir-fhir` placement: peer to `mimir-well`, or sub-submodule? | Founder | Pre-Sprint-1 |
| 2 | Write API in Phase 1: Patient/Encounter/Observation only, or all 20 read-only? | Founder | Sprint 6 design |
| 3 | OpenEMR Smart-on-FHIR support level — workable, or fallback to HAPI? | Founder + clinical advisor | Sprint 9 design |
| 4 | First demo audience: Beryl8/Prudential, friendly hospital, or internal-only? | Founder | Sprint 10 prep |
| 5 | Phase 1 deployment target: customer pilot, or stays on dev box? | Founder | Sprint 10 |

---

## Phase 1 Exit Criteria

Phase 1 is **complete** when all of these are signed off:

- [ ] All 10 sprints' acceptance criteria met
- [ ] 4 Goals (top of doc) green
- [ ] Demo recording exists for UC1 + UC3
- [ ] 78-element MOPH-PC1 conformance suite at 100% green
- [ ] R4↔R5 translator covers all renames + polymorphism merges + adherence extension
- [ ] 43Files adapter ingest verified against ≥1 real HOSxP dump
- [ ] Smart-on-FHIR launch flow proven end-to-end (OpenEMR or HAPI sandbox)
- [ ] Phase 1 retro doc filed
- [ ] Phase 2 backlog drafted (eir-ddx + first true Layer 2 module)

---

## References

- [ADR-006 FHIR canonical design](../decisions/ADR-006-fhir-canonical-design.md) — type system + 5 locked decisions (amended 2026-05-23 for R5 + 20 resources)
- [ADR-012 FHIR-native data plane](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md) — strategic positioning + 3-layer architecture
- [ADR-013 FHIR R5 canonical version](../decisions/ADR-013-fhir-r5-canonical-version.md) — version lock + R4 adapter boundary
- [ADR-009 single-tenant Mac mini](../decisions/ADR-009-single-tenant-mac-mini-deployment.md) — deployment shape
- [MOPH-PC1 FHIR mapping](../architecture/moph_pc1_fhir_mapping.md) — 78-element canonical reference
- [As-is problem analysis](../use-cases/as-is-problem-analysis.md) — 4 UC current-state + quantified impact
- [Strategic summary (CONFIDENTIAL)](../../../Asgard-Confidential/Mimir-FHIR/README.md) — consolidated view
- HL7 FHIR R5 spec — http://hl7.org/fhir/R5/
- FHIR Thailand IG — https://fhir.moph.go.th
- Smart-on-FHIR — https://docs.smarthealthit.org/

---

**This is a living plan.** Update on each sprint completion, scope change, or risk realisation. Phase 1 retro at end will inform Phase 2 plan structure.
