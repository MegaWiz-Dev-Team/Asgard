# FHIR R4 Resource Selection for Asgard

**Status:** Draft v1
**Date:** 2026-05-18
**Sprint:** 2 W2.4
**Scope:** Canonical patient-data types for the shared `asgard-doc-pipeline` crate
**Audience:** internal engineering
**Supersedes:** none
**Related:** [ADR-003 trait + shared crate](../decisions/ADR-003-shared-doc-pipeline-crate.md), planned ADR-006 (FHIR canonical), [dataset inventory plan](../../../Mimir/docs/04_evaluation_and_testing/04_10_dataset_inventory_plan_2026-05-17.md)

## 1. Goal

Pick the **smallest FHIR R4 resource set** that lets Asgard:

1. Represent patient data (medical chart OCR output, EHR ingest)
2. Represent insurance workflow (policy, claim, coverage)
3. Cross-domain integrate (insurance reads clinical, clinical writes insurance claims)
4. Bind to Thai coding standards (ICD-10-TM, TMT, TPC, LOINC, SNOMED CT)
5. Avoid over-implementation — full FHIR R4 has 150+ resources; we only need ~15

The selected set lives in the new `asgard-doc-pipeline-core` crate as Rust types (per [ADR-003](../decisions/ADR-003-shared-doc-pipeline-crate.md) §B.3). Consumers: Underwriter v3, medical chart OCR (Syn extension), future Mega Care portal bridge, future Eir agent tool outputs.

## 2. Non-goals

- **NOT a FHIR REST server** — we shape types for in-process Rust use, not for serving `GET /Patient/{id}` HTTP endpoints (that's a future workstream if/when external EHR integration is needed)
- **NOT exhaustive R4 coverage** — we skip resources that don't appear in any current workflow (e.g., Goal, CarePlan, NutritionOrder, Schedule, Slot)
- **NOT R5 or USCDI** — Thai market is on R4; R5 transition is unscheduled
- **NOT generic over all 150+ FHIR resources** — picking 15 means we can hand-tune Rust types, validation, and Thai profile extensions; a 150-resource library would force generic codegen patterns that miss Thai-specific needs

## 3. Selection summary

15 resources across 5 categories:

| # | Resource | Why | Primary Asgard consumer |
|---|---|---|---|
| **Clinical (10)** | | | |
| 1 | `Patient` | Identity, demographics, citizen_id, contact | All |
| 2 | `Encounter` | Visit context, admission, OPD/IPD | Medical chart OCR, Underwriter |
| 3 | `Observation` | Labs, vitals, sleep study metrics, BP/HR | Medical chart OCR, Eir-medtech |
| 4 | `Condition` | Diagnoses with ICD-10-TM coding | All clinical reasoning |
| 5 | `MedicationRequest` | Prescriptions with TMT coding | Eir-pharmacy, medical chart |
| 6 | `MedicationStatement` | Patient-reported med adherence | Medical chart, Eir-pharmacy |
| 7 | `Procedure` | Surgeries/procedures with TPC coding | Surgery, Underwriter pricing |
| 8 | `DiagnosticReport` | Lab reports, sleep study reports | Eir-medtech |
| 9 | `AllergyIntolerance` | Drug/food allergies, safety | Eir-pharmacy (mandatory check) |
| 10 | `DocumentReference` | Pointer to scanned/OCR'd chart docs | Medical chart OCR, Mega Care bridge |
| **Insurance (3)** | | | |
| 11 | `Coverage` | Active policy + beneficiary linkage | Underwriter, claim flows |
| 12 | `Claim` | Submitted insurance claim | Underwriter |
| 13 | `ClaimResponse` | Adjudication outcome | Underwriter |
| **Workflow / participants (2)** | | | |
| 14 | `Practitioner` | Physician/nurse identity (writer of orders) | All |
| 15 | `Organization` | Hospital/clinic/insurer entity | All |
| **Collection wrapper** | | | |
| (+) | `Bundle` | Wraps a set of resources for transport | All ingest/export |

`Bundle` is foundational and is implicit — every persistent set of resources is a Bundle. Doesn't count toward the 15.

## 4. Foundational datatypes (subset, included)

These are FHIR primitive/complex datatypes used by the resources above. We implement these instead of pulling a generic FHIR datatype library:

| Datatype | What it's for | Notes |
|---|---|---|
| `Identifier` | Business IDs (citizen_id, MRN, claim number) | Thai citizen_id system URI: `https://www.dopa.go.th/citizen-id` |
| `CodeableConcept` | Code + display text (links to a Coding) | The atom of medical coding |
| `Coding` | A single code from a code system | system + code + display |
| `Reference` | Pointer to another resource | `Reference(Patient/123)` or absolute URL |
| `HumanName` | Name parts (given, family, prefix) | Thai uses given+family only (no middle); prefix = นาย/นาง/นางสาว |
| `Address` | Postal address | Thai uses subdistrict (ตำบล) / district (อำเภอ) / province |
| `ContactPoint` | Phone/email | Thai phone format (+66 / 0XX) |
| `Period` | Date range | Used in Encounter.period, Coverage.period |
| `Quantity` | Numeric value with unit | Lab values, dose amounts |
| `Money` | Currency-aware amount | THB for all financial; ISO-4217 currency code |
| `Range` | Numeric range | Reference ranges in labs |
| `Annotation` | Free-text note with author + timestamp | Clinician notes |

We **do not** implement: `Attachment` body (just metadata via DocumentReference), `SampledData`, `Signature`, `Timing` (use ISO-8601 strings instead initially).

## 5. Per-resource spec — what we include and skip

For each resource we define a **lean Rust struct** with required fields + the optional fields Asgard actually uses. The full FHIR R4 spec has many optional fields we skip; we can extend later if a real consumer needs them.

### 5.1 Patient (with Thai profile)

```rust
pub struct Patient {
    pub id: Id,                        // UUID or stable hash
    pub identifier: Vec<Identifier>,   // citizen_id, MRN, passport
    pub active: bool,                  // default true
    pub name: Vec<HumanName>,          // Thai + transliterated
    pub gender: AdministrativeGender,  // male/female/other/unknown
    pub birth_date: Option<NaiveDate>, // YYYY-MM-DD
    pub address: Vec<Address>,
    pub telecom: Vec<ContactPoint>,
    pub marital_status: Option<CodeableConcept>,
    pub deceased: Option<bool>,
    pub general_practitioner: Vec<Reference>, // → Practitioner
    pub managing_organization: Option<Reference>, // → Organization (hospital)
}
```

**Thai profile (`ThaiPatient`) extends with:**
- `identifier` MUST include one with `system = "https://www.dopa.go.th/citizen-id"` and `value = <13-digit Luhn-valid>`
- `name` SHOULD include both Thai script (`use = "official"`) and Latin transliteration (`use = "usual"`)
- `address.country = "TH"` for domestic patients
- `address.line[0]` typically holds Thai house number + soi; `address.city = ตำบล`; `address.district = อำเภอ`; `address.state = จังหวัด`

**Skipped (FHIR has but we don't use yet):** `photo`, `contact[]` (emergency contacts — defer), `communication.language`, `link[]` (patient merging).

### 5.2 Encounter

```rust
pub struct Encounter {
    pub id: Id,
    pub identifier: Vec<Identifier>,    // visit number, admission number
    pub status: EncounterStatus,        // planned/in-progress/finished/cancelled
    pub class: Coding,                  // OPD / IPD / ER / virtual
    pub type_: Vec<CodeableConcept>,    // routine/follow-up/specialist
    pub subject: Reference,             // → Patient (required)
    pub participant: Vec<EncounterParticipant>, // → Practitioner
    pub period: Option<Period>,         // start + end
    pub reason_code: Vec<CodeableConcept>,
    pub reason_reference: Vec<Reference>, // → Condition
    pub diagnosis: Vec<EncounterDiagnosis>,
    pub hospitalization: Option<EncounterHospitalization>, // admission details (IPD only)
    pub service_provider: Option<Reference>, // → Organization
}
```

**Encounter.class** is the OPD/IPD distinguisher — important for Thai claims (different e-Claim formats per setting).

**Skipped:** `statusHistory`, `classHistory`, `length`, `account[]` (use Coverage instead).

### 5.3 Observation

```rust
pub struct Observation {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub status: ObservationStatus,      // registered/preliminary/final/amended/...
    pub category: Vec<CodeableConcept>, // vital-signs / laboratory / imaging
    pub code: CodeableConcept,          // LOINC code (e.g. 8480-6 = systolic BP)
    pub subject: Reference,             // → Patient
    pub encounter: Option<Reference>,
    pub effective: Option<ObservationEffective>, // dateTime | Period
    pub value: Option<ObservationValue>, // Quantity | string | CodeableConcept | Range | bool
    pub interpretation: Vec<CodeableConcept>, // H/L/A flags
    pub reference_range: Vec<ObservationReferenceRange>,
    pub component: Vec<ObservationComponent>, // for compound observations (e.g. BP = sys+dia)
}
```

**Code binding:** `Observation.code.coding` SHOULD use LOINC. For sleep-study metrics specifically (Mega Care domain):
- LOINC `93832-4` = sleep study summary
- LOINC `89026-8` = AHI (Apnea-Hypopnea Index)
- LOINC `96532-9` = ODI (Oxygen Desaturation Index)
- LOINC `8480-6` / `8462-4` = BP systolic/diastolic
- LOINC `4548-4` = HbA1c
- LOINC `2339-0` = glucose

**Skipped:** `derivedFrom`, `hasMember`, `device`, `bodySite`.

### 5.4 Condition (ICD-10-TM bound)

```rust
pub struct Condition {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub clinical_status: Option<CodeableConcept>, // active/recurrence/relapse/inactive/resolved
    pub verification_status: Option<CodeableConcept>, // unconfirmed/provisional/confirmed/refuted
    pub category: Vec<CodeableConcept>,
    pub severity: Option<CodeableConcept>,
    pub code: CodeableConcept,          // PRIMARY: ICD-10-TM coding
    pub subject: Reference,             // → Patient
    pub encounter: Option<Reference>,
    pub onset: Option<ConditionOnset>,  // dateTime | age | Period | Range
    pub recorded_date: Option<DateTime>,
    pub recorder: Option<Reference>,    // → Practitioner
    pub note: Vec<Annotation>,
}
```

**Thai profile (`ThaiCondition`):**
- `code.coding[]` MUST include at least one with `system = "https://moph.go.th/icd10-tm/anamai-moph-2010"` (or successor source_version)
- MAY include parallel SNOMED CT coding for cross-reference

**Skipped:** `bodySite`, `stage`, `evidence`, `asserter` (use recorder for both).

### 5.5 MedicationRequest (TMT bound)

```rust
pub struct MedicationRequest {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub status: MedicationRequestStatus, // active/on-hold/cancelled/completed/...
    pub intent: MedicationRequestIntent, // proposal/plan/order/...
    pub category: Vec<CodeableConcept>,  // inpatient/outpatient/community
    pub medication: MedicationReference, // CodeableConcept (TMT) | Reference(Medication)
    pub subject: Reference,              // → Patient
    pub encounter: Option<Reference>,
    pub authored_on: Option<DateTime>,
    pub requester: Option<Reference>,    // → Practitioner
    pub reason_code: Vec<CodeableConcept>,
    pub reason_reference: Vec<Reference>, // → Condition
    pub dosage_instruction: Vec<Dosage>,
    pub dispense_request: Option<DispenseRequest>,
    pub substitution: Option<Substitution>,
}
```

**Thai profile (`ThaiMedicationRequest`):**
- `medicationCodeableConcept.coding[]` SHOULD include a TMT code (`system = "https://thaiindustrial.go.th/tmt"` or current TMT URI)
- MAY include parallel RxNorm coding for international interop
- `dosageInstruction[].text` SHOULD use Thai language by default; `dosageInstruction[].timing` carries structured frequency

**Skipped:** `priorPrescription`, `detectedIssue[]` (use AllergyIntolerance + DDI tool output instead), `eventHistory`.

### 5.6 MedicationStatement

Same shape as MedicationRequest but:
- Patient-reported ("I'm taking …") vs prescribed
- Used for reconciliation, intake forms, OCR'd "current meds" sections
- `status` enum smaller (active/completed/not-taken/...)

### 5.7 Procedure (TPC bound)

```rust
pub struct Procedure {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub status: ProcedureStatus,
    pub category: Option<CodeableConcept>,
    pub code: CodeableConcept,          // TPC (Thai Procedural Classification)
    pub subject: Reference,             // → Patient
    pub encounter: Option<Reference>,
    pub performed: Option<ProcedurePerformed>, // dateTime | Period | Age | Range | string
    pub recorder: Option<Reference>,
    pub asserter: Option<Reference>,
    pub performer: Vec<ProcedurePerformer>,
    pub location: Option<Reference>,    // → Organization
    pub reason_code: Vec<CodeableConcept>,
    pub reason_reference: Vec<Reference>,
    pub body_site: Vec<CodeableConcept>,
    pub outcome: Option<CodeableConcept>,
    pub note: Vec<Annotation>,
}
```

**Thai profile:** `code.coding[]` SHOULD include TPC.

### 5.8 DiagnosticReport

Aggregates `Observation`s into a single report (lab report, sleep study report). Sleep clinic deliverable.

```rust
pub struct DiagnosticReport {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub status: DiagnosticReportStatus,
    pub category: Vec<CodeableConcept>,
    pub code: CodeableConcept,          // LOINC for report type
    pub subject: Reference,             // → Patient
    pub encounter: Option<Reference>,
    pub effective: Option<DiagnosticReportEffective>,
    pub issued: Option<DateTime>,
    pub performer: Vec<Reference>,
    pub result: Vec<Reference>,         // → Observation (the actual values)
    pub imaging_study: Vec<Reference>,  // → ImagingStudy (not implemented yet)
    pub media: Vec<DiagnosticReportMedia>,
    pub conclusion: Option<String>,
    pub conclusion_code: Vec<CodeableConcept>,
    pub presented_form: Vec<Attachment>, // PDF report — points to S3/MinIO URL
}
```

### 5.9 AllergyIntolerance

**Mandatory safety check** — eir-pharmacy MUST consult before any MedicationRequest action (per [Eir_Agents_Architecture §4.5](../../Eir/docs/Eir_Agents_Architecture.md)).

```rust
pub struct AllergyIntolerance {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub clinical_status: Option<CodeableConcept>,
    pub verification_status: Option<CodeableConcept>,
    pub type_: Option<AllergyIntoleranceType>, // allergy | intolerance
    pub category: Vec<AllergyIntoleranceCategory>, // food | medication | environment | biologic
    pub criticality: Option<AllergyIntoleranceCriticality>, // low | high | unable-to-assess
    pub code: CodeableConcept,          // substance code (TMT for drug, SNOMED for food)
    pub patient: Reference,             // → Patient
    pub onset: Option<AllergyOnset>,
    pub recorded_date: Option<DateTime>,
    pub recorder: Option<Reference>,
    pub note: Vec<Annotation>,
    pub reaction: Vec<AllergyReaction>,
}
```

### 5.10 DocumentReference

The bridge from OCR pipeline → FHIR. Each scanned chart + the extracted DiagnosticReport/Conditions all link back to one DocumentReference.

```rust
pub struct DocumentReference {
    pub id: Id,
    pub identifier: Vec<Identifier>,
    pub status: DocumentReferenceStatus,
    pub doc_status: Option<DocumentReferenceDocStatus>,
    pub type_: Option<CodeableConcept>,   // LOINC: e.g. 11502-2 = laboratory report
    pub category: Vec<CodeableConcept>,
    pub subject: Option<Reference>,       // → Patient
    pub date: Option<DateTime>,
    pub author: Vec<Reference>,           // → Practitioner | Organization
    pub authenticator: Option<Reference>,
    pub custodian: Option<Reference>,     // → Organization
    pub relates_to: Vec<DocumentReferenceRelatesTo>,
    pub description: Option<String>,
    pub security_label: Vec<CodeableConcept>,
    pub content: Vec<DocumentReferenceContent>, // file URI + mime-type + format
    pub context: Option<DocumentReferenceContext>, // encounter, event, period
}
```

**OCR pipeline integration:** Syn writes `DocumentReference` with `content[].attachment.url = "s3://asgard-medical-charts/{hash}.pdf"` + `content[].attachment.content_type = "application/pdf"`. Downstream `Condition`/`MedicationRequest` set `evidence.detail[]` referencing back to the DocumentReference.

### 5.11 Coverage

```rust
pub struct Coverage {
    pub id: Id,
    pub identifier: Vec<Identifier>,    // policy number
    pub status: CoverageStatus,         // active/cancelled/draft/entered-in-error
    pub type_: Option<CodeableConcept>, // HIP/EHCPOL/...
    pub policy_holder: Option<Reference>,
    pub subscriber: Option<Reference>,  // → Patient
    pub subscriber_id: Option<String>,
    pub beneficiary: Reference,         // → Patient (required)
    pub dependent: Option<String>,
    pub relationship: Option<CodeableConcept>, // self/spouse/child/...
    pub period: Option<Period>,
    pub payor: Vec<Reference>,          // → Organization (insurer)
    pub class: Vec<CoverageClass>,      // plan tier
    pub order: Option<u32>,             // primary/secondary
    pub network: Option<String>,
    pub cost_to_beneficiary: Vec<CoverageCostToBeneficiary>,
    pub subrogation: Option<bool>,
    pub contract: Vec<Reference>,
}
```

**Thai insurance:** `payor` references the insurer Organization (Prudential / ThaiLife / Thai Health). `policy_holder` may differ from `beneficiary` (employer-paid plans). `network` describes provider network for in-network/out-of-network claim handling.

### 5.12 Claim

```rust
pub struct Claim {
    pub id: Id,
    pub identifier: Vec<Identifier>,    // claim number
    pub status: FinancialResourceStatus,
    pub type_: CodeableConcept,         // institutional/professional/pharmacy
    pub sub_type: Option<CodeableConcept>,
    pub use_: ClaimUse,                 // claim/preauthorization/predetermination
    pub patient: Reference,             // → Patient
    pub billable_period: Option<Period>,
    pub created: DateTime,
    pub enterer: Option<Reference>,
    pub insurer: Option<Reference>,     // → Organization
    pub provider: Reference,            // → Practitioner | Organization
    pub priority: CodeableConcept,      // normal/stat/deferred
    pub funds_reserve: Option<CodeableConcept>,
    pub related: Vec<ClaimRelated>,
    pub prescription: Option<Reference>, // → MedicationRequest
    pub original_prescription: Option<Reference>,
    pub payee: Option<ClaimPayee>,
    pub referral: Option<Reference>,
    pub facility: Option<Reference>,
    pub care_team: Vec<ClaimCareTeam>,
    pub supporting_info: Vec<ClaimSupportingInfo>,
    pub diagnosis: Vec<ClaimDiagnosis>,
    pub procedure: Vec<ClaimProcedure>,
    pub insurance: Vec<ClaimInsurance>,
    pub accident: Option<ClaimAccident>,
    pub item: Vec<ClaimItem>,
    pub total: Option<Money>,           // THB
}
```

Long but each field maps to actual claim form requirements. Will likely trim during implementation if unused fields prove dead weight.

### 5.13 ClaimResponse

Adjudication result of a `Claim`. Mirrors Claim structure with `outcome`, `disposition`, `adjudication[]` per item, `total[]`, `payment`.

### 5.14 Practitioner

```rust
pub struct Practitioner {
    pub id: Id,
    pub identifier: Vec<Identifier>,    // medical license number, citizen_id
    pub active: bool,
    pub name: Vec<HumanName>,
    pub telecom: Vec<ContactPoint>,
    pub address: Vec<Address>,
    pub gender: Option<AdministrativeGender>,
    pub birth_date: Option<NaiveDate>,
    pub qualification: Vec<PractitionerQualification>, // medical degree, board cert
    pub communication: Vec<CodeableConcept>, // languages spoken
}
```

### 5.15 Organization

```rust
pub struct Organization {
    pub id: Id,
    pub identifier: Vec<Identifier>,    // หสนเลขทะเบียน, HSN/THCC, NHSO provider code
    pub active: bool,
    pub type_: Vec<CodeableConcept>,    // hospital/clinic/insurer/payer
    pub name: Option<String>,
    pub alias: Vec<String>,
    pub telecom: Vec<ContactPoint>,
    pub address: Vec<Address>,
    pub part_of: Option<Reference>,     // → Organization (parent)
    pub contact: Vec<OrganizationContact>,
    pub endpoint: Vec<Reference>,
}
```

## 6. Thai profile constraints (summary)

| Resource | Thai-specific constraint |
|---|---|
| Patient | Citizen ID identifier required, Thai script name MUST, address fields mapped to ตำบล/อำเภอ/จังหวัด |
| Condition | At least one ICD-10-TM coding in `code.coding[]` |
| MedicationRequest | TMT coding recommended in `medicationCodeableConcept.coding[]` |
| Procedure | TPC coding recommended |
| Coverage | `payor` Organization MUST be a registered Thai insurer per OIC list |
| Money | currency MUST be "THB" by default; foreign currency allowed only via explicit `currency` |
| Address | When country=TH: structure mapping per Thai postal hierarchy |

## 7. Resources explicitly NOT included (v1)

| Resource | Why excluded |
|---|---|
| `Goal`, `CarePlan` | No current workflow consumer |
| `Schedule`, `Slot`, `Appointment` | Mega Care portal handles its own booking; FHIR appointment not needed in core types |
| `Immunization` | Out of scope for Underwriter + Mega Care current focus |
| `FamilyMemberHistory` | Underwriter captures family hx as `Patient`-level Booleans (simpler) |
| `Specimen` | DiagnosticReport carries the lab values directly |
| `ImagingStudy` | Defer until image-multimodal Eir Radiology ships (Sprint 45+) |
| `Communication`, `CommunicationRequest` | Use HTTP audit + Tyr events instead |
| `Task` | Workflow orchestration handled by Bifrost, not FHIR Task |
| `Group` | No cohort use case yet |
| `EpisodeOfCare` | Encounter is sufficient; nesting deferred |
| `ExplanationOfBenefit` | Subset of ClaimResponse; cover with ClaimResponse extensions if needed |
| `Contract` | Defer; Coverage covers the linkage we need |
| `PaymentNotice`, `PaymentReconciliation` | Out of v1 scope |

If a future workstream needs one, add to v2.

## 8. Implementation note

Two paths considered for the Rust types:

### Option A: Hand-rolled types (recommended)
Write the 15 resources + datatypes as plain Rust structs with `serde::{Serialize, Deserialize}`. Pros: full control, no codegen complexity, Thai profile types live alongside, smaller compile time. Cons: ~3-5 days to land all 15.

### Option B: fhirbolt crate generation
Use [`fhirbolt`](https://crates.io/crates/fhirbolt) (R4 typed generators). Pros: full FHIR R4 surface in one dep, kept current with HL7 spec releases. Cons: drags in all 150 resources whether we use them or not, codegen patterns may clash with our `asgard-doc-pipeline-core` traits, Thai profile extension requires runtime check rather than typed.

**Decision:** Option A — hand-rolled for the 15. If a future workstream needs deep FHIR R4 (e.g. external EHR integration), introduce `fhirbolt` as a separate adapter crate at that boundary; don't pollute core.

## 9. Validation strategy

Per-resource validation lives in the type itself via constructor:

```rust
impl Patient {
    pub fn new_thai(citizen_id: ThaiCitizenId, ...) -> Result<Self, ValidationError> {
        // Validate Luhn checksum, name has Thai script, etc.
    }
}
```

Bulk validation utility:

```rust
pub fn validate_bundle(bundle: &Bundle) -> Vec<ValidationIssue>
```

Returns *all* issues, not first-fail, so importers can report comprehensively.

Validation runs:
1. On ingest (`asgard-doc-pipeline-core::ingest`) — log + reject non-conforming
2. On export (FHIR REST endpoint when one exists) — refuse to emit invalid
3. On test fixtures (CI) — every M3/I1 sample passes validation

## 10. Cross-references

- [ADR-003 trait-based extraction + shared crate](../decisions/ADR-003-shared-doc-pipeline-crate.md) — §B.3 lists FHIR core as a workspace member
- [Solution architecture: Agent/MCP/RAG/Graph](agent_rag_graph_solution_architecture.md) — Per-tenant section mentions FHIR as canonical
- [Underwriter v3 plan](../../../.claude/projects/-Users-mimir-Developer/memory/underwriter_v3_plan_decisions.md) — Phase B.3 schedules this work
- [Eir Agents Architecture](../../Eir/docs/Eir_Agents_Architecture.md) — §3.1 agents `read_fhir` tool depends on these types
- [Mega Care DATA_STANDARDS_RECOMMENDATIONS.md](../../../mega-care-admin-portal/docs/DATA_STANDARDS_RECOMMENDATIONS.md) — Mega Care side adopts the same R4 resources

## 11. Decision log

- 2026-05-18: Initial selection — 15 resources, hand-rolled, R4 only, Thai-profile via constraints. ADR-006 (to be written) will lock this.

## 12. Open questions

1. **Bundle entry typing:** `Bundle.entry[]` holds heterogeneous resources. Use Rust enum `BundleEntry { Patient(Patient), Condition(Condition), ... }` (closed, monomorphic) or `Box<dyn Resource>` (open, runtime dispatch)? Recommend enum for performance + exhaustive match safety.
2. **Versioning:** R4 has FHIR resource `meta.versionId` + `meta.lastUpdated`. Do we track resource history in Asgard storage, or treat resources as immutable + audit via Tyr? Recommend latter for v1.
3. **Schema discovery:** Should the crate expose JSON Schema for each Rust type so external consumers can validate? Recommend yes — generate with `schemars` crate.
4. **Loose vs strict parsing:** Inbound FHIR from external systems may include fields we skip. Recommend deny-unknown-fields when reading our own data, allow-and-ignore when parsing external.
5. **i18n / locale:** Should Rust types carry a `Locale` enum for which language the human-readable fields are in? Recommend no — store as `string` with optional `_language` extension per FHIR convention.
