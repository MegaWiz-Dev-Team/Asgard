# DESIGN DRAFT — Medical Document Digitization Platform

Status: **Draft / design only** — no code. Review before promoting to ADR.
Author: (Claude assist, 2026-05-29)
Related: ADR-006 (Syn OCR Stack), ADR-007 (Skuggi PII), ADR-013 (FHIR R5 canonical),
`Syn/docs/adr/draft-vlm-checkbox-mode.md`, `medical_claims_pipeline`, `uc2_patient_summary`

---

## 1. Vision

Turn **paper / handwritten / scanned Thai medical documents → a canonical digital
record (FHIR R5)** that any use case can consume. The claims portal (Iris) is the
first consumer, but the digitized record is intentionally **claim-agnostic** — the
same pipeline serves patient summaries, EHR back-capture, underwriting, and research.

We have been building the pieces ad hoc (OCR → classify → checkbox → figure →
review/annotate → FHIR). This design names them as ONE reusable capability so we
build the core **once** and add thin adapters per use case (per
`feedback_consolidate_overlap_early` — extract the shared core from day 1, don't
fork-then-merge).

> One sentence: **"A scanned OPD card in, a FHIR R5 Bundle + provenance sidecar out;
> claims/summary/research are adapters on the Bundle."**

## 2. Use cases (claims is 1 of N)

| Consumer | Uses the digital record to… |
|---|---|
| **Claims (Iris)** | FHIR Bundle → NHSO XML / สปสช EDI 837-I |
| **Patient summary** (eir-clinical) | FHIR Composition → clinician summary (uc2) |
| **EHR back-capture** | Import legacy paper charts into the EHR |
| **Underwriting** (insurance) | Extract conditions/meds from submitted medical docs |
| **Living evidence / research** | De-identified structured corpus (asgard_living_evidence) |
| **OCR fine-tune** | Review corrections → labeled training data (free annotation) |

Designing only for claims would force a rebuild for each of these. Designing for the
**record** makes them adapters.

## 3. Architecture — layered pipeline

```
 INGEST            any image/PDF, any source (upload, scanner, fax, DICOM-SR)
   │
 1 CLASSIFY        document type  (form-code rule → VLM/classifier fallback)
   │                 e.g. HA-FO-033 → "medical_history_report"
 2 LAYOUT          region detection (Syn region pipeline v0.3.0):
   │                 printed | handwritten | mixed | table | checkbox | figure | stamp
 3 RECOGNIZE       per-region engine:
   │                 text→OCR(Typhoon MLX local) · checkbox→☑/☐ · table→TableTransformer
   │                 figure→crop+hash (no OCR) · stamp→hash-only
 4 EXTRACT         text+regions → clinical entities, guided by doc-type TEMPLATE
   │                 (field map: where Dx/meds/vitals/checkbox-options live per form)
 5 ASSEMBLE        entities → FHIR R5 resources  (via mimir-fhir crate)
   │                 Condition · MedicationRequest · Observation · Composition ·
   │                 DocumentReference · Media · Provenance         → FHIR Bundle
 6 REVIEW          human correction (left=image, right=fields, group by document)
   │                 store original + corrected  → annotation/provenance sidecar
 7 ADAPTERS        Bundle → { NHSO/สปสช claim | patient summary | EHR | research }
```

Steps 1–4 are **document/measurement** concerns (Syn's domain). Step 5 is the
**clinical-semantic** boundary (mimir-fhir). Steps 6–7 are product surfaces.

## 4. Two data layers + Provenance bridge

Decided earlier in the design thread; restated as the platform invariant.

- **Clinical layer = FHIR R5** (canonical, via mimir-fhir). The "truth."
- **Annotation/provenance layer = custom doc-centric schema** (regions, bbox,
  checkbox state, figures, OCR engine, confidence, **original vs corrected** value).
  FHIR has no home for "this box at bbox X is ticked / OCR said Y, human fixed to Z."
- **Bridge = FHIR `Provenance`** + `meta.source` + extensions: every resource points
  back to its document region, engine, confidence, and original OCR value.

```
Condition(bedsore gr.IV, L89.x)
  └─Provenance→ doc_id, page, bbox, engine=typhoon-q8, conf=0.7,
                original="Bedsore gr IV", corrected_by=clinician@…
```

The annotation layer is simultaneously: the **review** data model, the **GT** for OCR
eval, and the **fine-tune** correction-pair store. One schema, four jobs.

## 5. Doc-type template registry (the extensibility seam)

Each document type has a template that says *where its fields live and how they map
to FHIR*. Adding a new form = adding a template, not changing the pipeline.

```jsonc
// templates/medical_history_report.json   (form_code: HA-FO-033)
{
  "doc_type": "medical_history_report",
  "match": { "form_code": "HA-FO-033", "title_contains": ["MEDICAL HISTORY"] },
  "fields": [
    {"key":"chief_complaint","region":"handwritten","fhir":"Composition.section[cc]"},
    {"key":"underlying_dx","region":"handwritten","fhir":"Condition[]"},
    {"key":"drug_allergy","region":"checkbox","group":"drug_allergy",
       "fhir":"AllergyIntolerance|data-absent"}
  ]
}
```

Registry lives with the digitization service; templates are data, versioned, and
themselves reviewable. This is what lets the platform absorb the long tail of Thai
hospital forms without code churn.

## 6. Component ownership (no new Norse component)

Per `feedback_no_new_norse_components` — extend existing, plain-English submodules.

| Layer | Owner | Notes |
|---|---|---|
| Ingest, classify, layout, recognize (1–3) | **Syn** | core OCR/region pipeline (v0.3.0); checkbox via `draft-vlm-checkbox-mode` |
| Doc-type templates + extract (4) | **Syn submodule** (e.g. `syn-forms`) | template registry + field extraction |
| FHIR assembly (5) | **mimir-fhir** crate consumer | **never reimplement FHIR types** elsewhere |
| Annotation/provenance store (6) | shared (Mimir eval tenant + Syn review-queue) | original/corrected; feeds fine-tune |
| Adapters (7) | each consumer | Iris=claims, eir-clinical=summary, … |

No new top-level component. The "platform" is the **contract** (FHIR Bundle +
provenance sidecar) plus the template registry — not a new service.

## 7. FHIR R5 gating reality (checked 2026-05-29)

`mimir-fhir` is **v0.0.1 — datatypes only**. Resources (Condition, Observation,
MedicationRequest, Composition, DocumentReference, Provenance, Media) are
**commented out** in `lib.rs` ("Sprint 2-10 — not yet implemented"). So step 5 cannot
assemble real FHIR resources today.

**Consequence + plan:**
1. **Digitization drives the mimir-fhir Sprint 2 priority.** The resource subset this
   platform needs — `Condition, MedicationRequest, Observation, Composition,
   DocumentReference, Media, Provenance` — becomes the crate's next-sprint scope.
   (Note: `medical_claims_pipeline` already flagged Composition + MedicationRequest as
   needed; Composition was NOT in the original 20-resource MOPH-PC1 set → scope +1.)
2. **Don't hand-roll FHIR in Syn/Iris** to "unblock" — that violates the
   never-reimplement rule and creates drift. Instead:
3. **Interim neutral struct.** Steps 1–4 already produce a neutral
   `StructuredDocument` (entities + regions + provenance). Until mimir-fhir ships
   resources, the **FHIR adapter (step 5) is a stub** and claims map
   `StructuredDocument → NHSO` directly (Iris already does this). When the crate lands
   resources, step 5 becomes real and every consumer gets FHIR for free. The neutral
   struct is NOT a FHIR reimplementation — it's the pre-FHIR extraction payload.

So: the platform is **designed FHIR-first, built FHIR-deferred** — claims ships on the
neutral struct now; FHIR slots in without reworking steps 1–4 or the adapters' inputs
once mimir-fhir resources exist.

## 8. PII / local / Tenant / Tyr

- **Local-only by default.** OCR + checkbox + extraction run on local MLX (Typhoon /
  Qwen-VL / Gemma) — real patient docs are PHI; cloud is barred for insurance
  (`insurance_skuggi_gating`) and for raw PHI generally (`syn_data_internal_only`).
- **Tenant:** raw digitized records → `asgard_medical` (PHI); de-identified /
  hash-only metrics → `asgard_platform`. Research export → de-identified bundle only.
- **Tyr** is a first-class detection layer over every digitization run
  (`feedback_include_tyr_in_pii_designs`), not an afterthought: PII surface +
  regulated-decision (claim/underwriting) output.
- **Figures/sketches** → `Media`/`DocumentReference`, image-hashed; the drawing is
  never OCR'd as text, but its surrounding annotations are extracted.

## 9. Reusability — adding a use case

A new consumer does NOT touch steps 1–6. It:
1. Reads the FHIR Bundle (or interim `StructuredDocument`).
2. Adds a doc-type template if its forms are new.
3. Writes an output adapter (step 7).

E.g. "discharge-summary digitization" = new template + a Composition-rendering adapter;
everything else is reused.

## 10. Phasing

| Phase | Deliverable | Depends on |
|---|---|---|
| P0 | Neutral `StructuredDocument` schema + doc-type template registry + classify step | Syn region pipeline |
| P1 | Review-as-annotation (left/right, original+corrected) + Mimir annotation store | P0; Iris UI |
| P2 | Checkbox extraction (VLM q8 or OCR-native) | `draft-vlm-checkbox-mode` POC |
| P3 | **FHIR R5 assembly adapter** | **mimir-fhir resources (Sprint 2+)** ← gating |
| P4 | Additional consumers (summary, EHR, research) | P3 |

Claims ships at P1 (neutral struct → NHSO); FHIR (P3) is an upgrade, not a prerequisite.

## 11. Out of scope (this design)

- Wound/figure image classification model (figures captured + tagged for future only).
- Auto-submission to NHSO/สปสช portals.
- Real-time scanning hardware integration.
- Non-medical document types.
