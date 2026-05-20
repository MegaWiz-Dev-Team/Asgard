# ADR-008 — Structured Lab Extraction with HITL Review (syn-review)

**Status:** Accepted (2026-05-13)
**Date:** 2026-05-13
**Sprint:** TBD (proposed S1/S2 after Syn S1 OCR foundation lands)
**Related ADRs:**
- ADR-006 (Syn OCR Stack) — provides the raw text/image extraction layer this builds on
- ADR-007 (Skuggi PII Guardrail) — gates which model backend the extractor may use
- ADR-001 (Curator) — HITL design principles for clinical review surfaces

## Context

Syn's S1 OCR pipeline (ADR-006) delivers `extracted_text` from lab report PDF / image, and the existing E2E flow (Asgard/docs/technical/e2e-ocr-lab-icd10.md) wires that into Eir for ICD-10-TM coding. That covers **prose-aware diagnosis coding** but does **not** produce a structured `LabRecord` with per-analyte values, units, ref ranges, and validation state.

Two downstream consumers need that structured form:

1. **`asgard_insurance` underwriting** — actuarial risk scoring requires standardized analyte codes + normalized units + explicit missing-value semantics. Wrong values translate directly to mispriced premium = regulatory exposure (คปภ.).
2. **`asgard_medical` Eir variants (eir-internal-medicine, eir-ent, eir-cardio, eir-sleep)** — RAG context for clinical reasoning prefers raw values + flags + trend across multiple lab reports for the same patient.

Today, both would either (a) re-OCR and re-parse the same document in different tenants — wasteful and inconsistent, or (b) consume free-text from Syn — error-prone for actuarial features.

We also need a **human-in-the-loop review surface** before either consumer ingests the data, because:

- Lab data wrong → underwriting wrong → regulatory + customer harm
- Volume is initially low (10-100 docs/day, expected ramp); validation rules can auto-approve high-confidence rows; reviewer focuses on flagged cells only
- Reviewer in initial phase = the founder (Thai-native, bilingual technical literacy) → UI vocab Thai/English with LOINC/ICD tooltip

A naming caution: an earlier conversation proposed "Forseti" for this surface, but `/Users/mimir/Developer/Forseti` already exists as an LLM-powered E2E testing service. The new functionality lives **inside Syn** as a sub-module — `syn-review` — not a new top-level component.

Vendor template per-lab is **explicitly out of scope** for S1: vendor mix is not yet known; layout-agnostic VLM extraction handles unknown templates from day 1. Templates are S3+ optimization if volume justifies it.

## Decision

**Add a new Syn sub-module `syn-review` that produces a FHIR-aligned `LabRecord` from Syn OCR output, gated by a rule-driven validation layer, with a single HITL surface for review before downstream consumption.**

### Pipeline shape

```
PDF / image
   │
   ▼
Syn OCR (existing, ADR-006)                 # text + bbox + engine confidence
   │
   ▼
syn-extract (NEW)                            # text → LabRecord JSON
   │  ├─ VLM stage (model per tenant — see Model Routing below)
   │  ├─ OCR cross-check stage              # VLM value vs Syn OCR value per cell
   │  └─ LOINC mapping stage                 # raw analyte → canonical code
   │
   ▼
syn-validate (NEW)                           # rule engine; per-cell pass/fail
   │
   ▼
auto-approve? ────yes──► canonical LabRecord (status=approved, auto=true)
   │ no
   ▼
syn-review (NEW, HITL UI)                    # reviewer corrects flagged cells
   │
   ▼
canonical LabRecord (status=approved)
   │
   ├─► asgard_medical: Eir RAG context, ICD-10-TM coding
   └─► asgard_insurance: underwriting feature pipeline
```

### Model routing per tenant

| Tenant | VLM stage | Cloud allowed | Reason |
|---|---|---|---|
| `asgard_medical` | Qwen2.5-VL-7B local (MLX via Heimdall) → Gemini Flash if confidence low | Yes, opt-in | ADR-006 router; Eir already uses cloud for hard cases |
| `asgard_insurance` | Gemma 3 27B local-only | **No** | Skuggi gating ([insurance_skuggi_gating memory](../../../.claude/projects/-Users-mimir-Developer/memory/insurance_skuggi_gating.md)); Skuggi W2/W3/W4 must ship before relaxing |

Routing logic reuses Syn's smart router (extends rule #2: `ocr_phi_strict` already maps cleanly to insurance tenant). Adds rule for VLM tier selection alongside OCR tier selection.

### Canonical LabRecord schema (FHIR-aligned subset)

Schema is a subset of HL7 FHIR R6 `DiagnosticReport` + `Observation` (with R6's new `organizer` element for panel grouping) — enriched with Asgard-specific provenance, review state, and underwriting feature precomputation. This lets us:

- Serialize directly to FHIR for future EHR interop without remodeling
- Map analyte codes via LOINC (industry standard; 80 codes cover 80% of lab volume — feasible focused mapping)
- Map units via UCUM (LOINC pairs with UCUM by design)
- Use FHIR's `dataAbsentReason` for "test was not performed" vs "error" — critical for underwriting feature completeness

```yaml
LabReportDocument:
  meta:
    resource_type: "DiagnosticReport"
    fhir_profile: "us-core-diagnosticreport-lab"  # forward-compat
    tenant_id: "asgard_medical" | "asgard_insurance"
    document_id: uuid
    ingest:
      source_uri: string
      mime_type: "application/pdf" | "image/jpeg" | "image/png"
      hash_sha256: string                  # idempotency on re-upload
      ts: ISO8601
      actor: {type, id}
    extraction:
      pipeline_version: semver
      ocr_engine: "paddle"|"typhoon"|"gemini-flash"|"gemini-pro"
      ocr_audit_id: string                 # links to Syn audit row
      vlm_model: string                    # "qwen2.5-vl-7b" | "gemma-3-27b" | "gemini-3-flash"
      vlm_confidence: 0.0–1.0
      router_reason: string
    review:
      status: "pending"|"in_review"|"approved"|"rejected"
      reviewer_id: string|null
      reviewed_at: ISO8601|null
      correction_count: int
      auto_approved: bool

  subject:                                 # FHIR Patient ref (tokenized)
    patient_token: string                  # NOT raw HN; Skuggi-redacted
    sex: "M"|"F"|"O"|null
    dob_year: int|null                     # year only; full DOB is PII
    age_at_collection: int|null

  performer:                               # FHIR Organization
    vendor_detected: string|null           # "BKK Lab" / "N Health" / ...
    vendor_confidence: 0.0–1.0
    lab_license_no: string|null            # MoPH lab license

  effectiveDateTime: ISO8601               # specimen collection
  issued: ISO8601                          # report issue
  specimen:
    type: "blood"|"urine"|"saliva"|"swab"|"other"
    type_loinc: string|null
    fasting_status: bool|null

  observations:                            # FHIR Observation (one per analyte)
    - id: "obs-1"
      organizer: "lipid-panel"|"liver-panel"|null   # FHIR R6 organizer
      code:
        loinc: "2093-3"
        loinc_display: "Cholesterol [Mass/volume] in Serum or Plasma"
        raw_text_th: "โคเลสเตอรอลรวม"
        raw_text_en: "Total Cholesterol"
        mapping_confidence: 0.0–1.0
      value:
        quantity: 195                      # null if non-numeric
        comparator: null|"<"|">"|"<="|">=" # FHIR detection-limit pattern
        unit_ucum: "mg/dL"                 # canonical
        unit_raw: "mg/dL"                  # as printed (may differ)
      reference_range:                       # vendor-printed, verbatim
        low: number|null
        high: number|null
        unit_ucum: string
        type: "normal"|"therapeutic"|"critical"|"recommended"
      canonical_reference_range:             # clinical canonical, used by validation
        low: number|null
        high: number|null
        unit_ucum: string
        source: "loinc-canonical"|"asgard-curated"
      interpretation: "N"|"L"|"H"|"LL"|"HH"|"A"|null   # FHIR v2-0078 subset
      data_absent_reason: null|"error"|"NaN"|"not-performed"|"masked"
      method: string|null
      provenance:
        ocr_confidence: 0.0–1.0
        vlm_confidence: 0.0–1.0
        source_pages: [int]
        bbox: [x, y, w, h]|null
        cross_check_agreement: bool        # VLM ↔ OCR cell match
      validation:
        rules_passed: [string]
        rules_failed: [string]
        plausibility: "pass"|"fail"|"unreviewable"
      review_meta:
        auto_approved: bool
        original_value: any                # before any human edit
        corrected_value: any|null
        reviewer_note: string|null

  panels_summary:                          # convenience for clinical readability
    lipid: {total_chol, ldl, hdl, triglycerides, ratio_total_hdl}
    glucose: {fasting_glucose, hba1c, postprandial_glucose}
    liver: {alt, ast, alp, ggt, bilirubin_total, bilirubin_direct, albumin}
    kidney: {creatinine, egfr, bun, urea}
    cbc: {wbc, rbc, hb, hct, plt, mcv, mch, mchc}
    thyroid: {tsh, ft4, ft3}
    inflammation: {crp, esr}
    # ... populated only when relevant LOINCs are present

  underwriting_features:                   # asgard_insurance ONLY — null in medical tenant
    smoker_indicator:
      detected: bool|null
      cotinine_value: float|null
    metabolic:
      hba1c_band: "<5.7"|"5.7-6.4"|">=6.5"|null
      fasting_glucose_band: "<100"|"100-125"|">=126"|null
    cardiovascular:
      ldl_band: "<100"|"100-129"|"130-159"|"160-189"|">=190"|null
      hdl_low_male: bool|null              # <40 mg/dL
      hdl_low_female: bool|null            # <50 mg/dL
      total_hdl_ratio: float|null
    hepatic:
      alt_elevated: bool|null              # >40 U/L typical
      ast_alt_ratio: float|null
    renal:
      egfr_band: ">=90"|"60-89"|"30-59"|"<30"|null
    feature_completeness: 0.0–1.0          # fraction of expected fields present
```

### Validation rule engine

Stateless function `validate(observation) -> {passed: [...], failed: [...], plausibility}`. Rule library is data-driven (YAML in `Syn/services/syn-validate/rules/`):

- **Type rules** (R1xx): numeric fields contain only `[0-9.,<>=-]`; date fields parse to ISO; UCUM unit in controlled vocab
- **Range rules** (R2xx): per-LOINC plausibility envelope (e.g., glucose 0–2000 mg/dL; >2000 = fail, not approve-as-extreme)
- **Consistency rules** (R3xx): same analyte in one document → same unit; ref range bounds make sense (low < high); interpretation flag matches value vs range
- **Underwriting-specific rules** (R4xx, only in insurance tenant): stricter band-edge handling (HbA1c boundary 6.5 = decisive value, not a rounding zone — force human verification)

Auto-approve gate: all type + range + consistency rules pass AND ocr+vlm cross-check agrees AND vlm_confidence > 0.90 → auto-approve cell. Otherwise flag for HITL.

Per-tenant threshold override:
- `asgard_medical`: row-level auto-approve threshold 0.85
- `asgard_insurance`: 0.95 (stricter; underwriting actuarial exposure)

### HITL UI (`syn-review`)

- **Tech**: Leptos + WASM (per existing Asgard Rust preference; rationale: PDF rendering via pdf.js works fine through wasm-bindgen, virtualized grid not needed at this volume but the Leptos foundation makes it easy to add later)
- **Layout**: split pane — PDF preview left, observations grid right; click cell → bbox highlights on PDF
- **Cell colors**: green = auto-approve candidate, yellow = validation flag, red = OCR/VLM disagreement + flag
- **Vocab toggle**: Thai/English (persisted per-reviewer); cell hover shows LOINC + display + UCUM unit + ref range source as tooltip
- **Bulk operations**: approve-all-green within column / panel (keyboard `A`); jump-to-next-flag (`N`)
- **Audit**: every approve / reject / correction emits Tyr event with diff; reviewer note required for any value change

### Tyr integration

Per [feedback_include_tyr_in_pii_designs](../../../.claude/projects/-Users-mimir-Developer/memory/feedback_include_tyr_in_pii_designs.md): events emitted for:

- Document ingest (tenant, source, hash)
- Extraction completion (model used, confidence, auto-approve ratio)
- HITL session start/end (reviewer, duration, correction count)
- Per-cell correction (original value → new value, reviewer, timestamp, note)
- Downstream consumer access (which Eir variant / underwriting service pulled the LabRecord, when)

This gives the regulator-facing audit trail in one place.

## Options considered

### A. Label Studio self-hosted as the HITL surface
- ✅ Ships fast, mature OSS, ML Backend pattern fits Syn pre-fill
- ✅ Self-hostable under tenant boundary
- ❌ Python/Django heavyweight; introduces its own Postgres for annotation state — must sync to canonical LabRecord
- ❌ Table editing UX is workable but not great; not the failure mode at 10-100/day but problematic if volume scales
- ❌ Adds a new deploy target with its own auth + ops surface area
- **Rejected for primary surface; revisit as fallback** if syn-review build slips

### B. Build inside Mimir instead of Syn
- ✅ Mimir already hosts agent execution and the `icd10_tm_lookup` machinery; structured extraction "wants to live near the agent"
- ❌ Mimir's identity is RAG/knowledge; document processing is Syn's
- ❌ Conflates two concerns; harder to evolve independently
- **Rejected** — wrong ownership

### C. New top-level component (originally proposed: "Forseti", "Vör")
- ❌ Conflicts with existing `/Users/mimir/Developer/Forseti` (E2E test service)
- ❌ Violates [feedback_no_new_norse_components](../../../.claude/projects/-Users-mimir-Developer/memory/feedback_no_new_norse_components.md) — function fits inside Syn
- ❌ Extra repo + deploy + ownership for no architectural gain
- **Rejected**

### D. Defer HITL; rely on validation rules alone
- ✅ Faster to ship
- ❌ Underwriting volume even at 10-100/day produces ~5-10 flagged docs/day where rules cannot decide; without HITL these block the pipeline or auto-approve incorrectly
- ❌ No mechanism to catch systematic OCR/VLM bias (e.g., consistent unit misread on a vendor template); HITL corrections are the training signal
- **Rejected** — accuracy compounds with reviewer feedback loop

### E. Vendor template library from day 1
- ✅ Higher extraction accuracy if templates match
- ❌ Vendor mix not yet known; would block on data we don't have
- ❌ Brittle: every new vendor needs new template
- **Rejected for S1; revisit S3+** once 1-3 months of real document mix is observed and template ROI is computable

## Non-goals

- Multi-page PDF specific handling (same as Syn S1; deferred)
- Non-lab document types (referral, sleep study narrative, insurance claim) — designed to fit the same pipeline but explicitly out of S1/S2 scope
- Vendor template detection beyond opportunistic `vendor_detected` field
- Real-time collaborative review (single reviewer at this volume)
- Mobile UI (desktop reviewer assumed)

## Consequences

**Positive:**
- FHIR-aligned schema enables EHR interop later without remodeling
- Single canonical record serves both tenants without re-extraction
- Validation engine catches the lion's share of issues before reviewer; reviewer time is high-value-only
- Skuggi gating leveraged transparently — insurance tenant cannot accidentally call cloud models
- Tyr gets first-class audit trail across the full extraction → review → consume path

**Negative:**
- Initial LOINC mapping work for top ~80 Thai lab analyte names (one-time but real)
- Two model backends (cloud-allowed vs local-only) means two evaluation harnesses
- HITL UI is non-trivial Leptos work; mitigated by tight scope (table editor + PDF preview, no annotation drawing)

**Reversal cost:** Schema can extend (FHIR-aligned design forward-compat); model routing can swap (Heimdall abstracts); only the UI is structurally hard to reverse. So: build the schema + validation engine first, prove with simple CLI/admin tool before investing in Leptos UI. UI is the last 30% of S1.

## Phase sequencing (proposed)

| Phase | Scope | Deliverable |
|---|---|---|
| **P1 (2w)** | Canonical schema + validation engine + LOINC top-80 mapping + VLM extraction stage (cloud, medical tenant) | CLI: `syn-extract path/to/lab.pdf --tenant asgard_medical` → JSON |
| **P2 (1.5w)** | Local model backend (Gemma 3 27B vision) + insurance tenant variant + underwriting feature engineering | Same CLI, `--tenant asgard_insurance` flag works end-to-end |
| **P3 (2w)** | `syn-review` Leptos UI + Tyr event emit + reviewer assignment (single reviewer for now: founder) | Browser flow: upload → auto-approve or review → approved LabRecord stored |
| **P4 (1w)** | Eir consumer integration (eir-internal-medicine clone + eir-ent context plumbing) | Existing E2E test (e2e-ocr-lab-icd10) extended to assert LabRecord ingest |
| **P5 (1w)** | Underwriting consumer stub + actuarial feature export | API: `GET /api/v1/lab-records/{id}/underwriting-features` |

Total ~7.5 weeks across ~2 sprints.

## Resolved questions (2026-05-13)

1. **LabRecord storage** → MariaDB `lab_records` (one row per document, JSON blob of full record) + denormalized `lab_observations` table (one row per analyte for query). Row-level `tenant_id` filter via Bifrost (not per-tenant schemas).
2. **Eir-internal-medicine** → clone from Eir base in P4 (อายุรเวช preamble + lab-aware tool allowlist).
3. **PSA / tumor markers** → not in initial schema; survey first 100 real documents and add via schema extension if pattern appears.
4. **Reference range** → store both. `observation.reference_range` = vendor-printed verbatim. Separate `observation.canonical_reference_range` (new field added below) used by `validation.plausibility` rule.

## References

- HL7 FHIR Observation R6 ballot, especially `organizer` element for panel grouping: https://build.fhir.org/observation.html
- US Core Laboratory Result Observation Profile (target compatibility): https://build.fhir.org/ig/HL7/US-Core/StructureDefinition-us-core-observation-lab.html
- LOINC: https://loinc.org/guides/
- UCUM unit value set: https://build.fhir.org/valueset-ucum-units.html
- Life insurance lab panel landscape (HbA1c, LDL, ALT/AST, eGFR, cotinine): https://www.moneygeek.com/insurance/life/life-insurance-blood-test/
- Existing Asgard E2E lab flow (this ADR builds on it): [Asgard/docs/technical/e2e-ocr-lab-icd10.md](../technical/e2e-ocr-lab-icd10.md)
