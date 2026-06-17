# UC1 — OPD HT/DM Follow-Up View: Design Spec

**Status:** Draft (companion to Sprint 10 demo plan)
**Date:** 2026-05-27
**Owner:** paripol@megawiz.co
**Sprints affected:** 9 (Smart-on-FHIR launch), 10 (demo + 5 patient fixtures)

## Purpose

UC1 is one of three Sprint 10 demos validating the mimir-fhir Phase 1 stack. Unlike [UC2 patient summary](composition-uc2-patient-summary-spec.md) (LLM-generated FHIR Composition) and UC3 paediatric immunization (deterministic vaccine-schedule logic), **UC1 is a pure read-only UI view** of structured FHIR data. No LLM reasoning, no skill, no tool repertoire — just a Smart-on-FHIR app that fetches resources from `mimir-fhir` REST and renders them.

UC1 exists primarily to **demonstrate the end-to-end data flow** (43Files → mimir-fhir → Smart-on-FHIR app → clinician) for the most common Thai primary care scenario (hypertension + diabetes follow-up).

## 1. Scope

A Smart-on-FHIR app launched from OpenEMR's "Asgard Decision Support" button. Shows a single screen with five tiles for a patient with active HT and/or T2DM:

| Tile | Source | Render |
|---|---|---|
| 1. Patient header | `Patient` (CID, name, age, sex) | one-line header with citizen ID slice + Thai name |
| 2. BP trend | `Observation` LOINC 85354-9 (BP panel), last 4 encounters | sparkline + most-recent reading + target range marker |
| 3. HbA1c trend | `Observation` LOINC 4548-4, last 4 results | sparkline + most-recent + target <7% marker |
| 4. Active problems | `Condition` where `clinicalStatus=active`, filtered to circulatory/endocrine ICD-10 chapters | list with date-recorded |
| 5. Active medications | `MedicationStatement` where `status in {recorded, active}` + `MedicationRequest` where `status=active`, deduplicated by TMT | list with dose + frequency + adherence flag |

No interactive features, no edits, no LLM generation. The clinician reads and decides; the app does not recommend.

## 2. Data contract — mimir-fhir REST queries

Five parallel HTTPS calls on app launch, with patient ID resolved from the Smart-on-FHIR launch token:

```
GET  /fhir/Patient/{id}
GET  /fhir/Observation?patient={id}&code=85354-9&_count=4&_sort=-date
GET  /fhir/Observation?patient={id}&code=4548-4&_count=4&_sort=-date
GET  /fhir/Condition?patient={id}&clinical-status=active
GET  /fhir/MedicationStatement?patient={id}&status=recorded,active
GET  /fhir/MedicationRequest?patient={id}&status=active
```

All queries use the Asgard FHIR Profile binding per [ADR-016](../decisions/ADR-016-asgard-fhir-profile-family.md); validation per [ADR-019](../decisions/ADR-019-fhir-profile-validation-tightest-binding-wins.md). Patient identifier slice per [ADR-020](../decisions/ADR-020-43files-hosxp-fhir-adapter.md) D3 (CID + HN + PID + Asgard UUID).

Filter narrowing for Tile 4 (Problems): client-side filter to ICD-10 chapters I (Circulatory) and E (Endocrine). Server-side filter is also acceptable; defer to UI implementer.

Token budget: not applicable (no LLM). p95 fetch budget ≤500ms for all 6 calls in parallel.

## 3. UI component spec

Layout: single-page responsive view, vertical stack on mobile, 2-column grid on tablet+.

### 3.1 Patient header (Tile 1)

```
┌─────────────────────────────────────────────────────────┐
│ สมชาย วงศ์มาลัย  ♂ 58y  CID 1234567890123  HN A23-4567   │
└─────────────────────────────────────────────────────────┘
```

- Name renders in Thai if `Patient.name.use=usual` has Thai script; otherwise English
- Age computed from `birthDate` at launch time
- CID + HN from `identifier[]` slices (per ADR-020 identifier model)
- No PHI displayed beyond what OpenEMR already shows in the launching context

### 3.2 BP trend (Tile 2)

```
┌─────────────────────────────────────────────────────────┐
│ Blood Pressure                                          │
│   140 ●─────●                                           │
│       └●─────●─── target ≤130                           │
│        20 Apr  18 May                                   │
│ Most recent: 142/88 mmHg (18 May 2026)                  │
└─────────────────────────────────────────────────────────┘
```

- Sparkline of systolic (top series) + diastolic (bottom series) over last 4 BP readings
- Target line at 130/80 (general adult target) — color-coded green if at goal, amber if marginal, red if above
- Date labels on x-axis (last and first only to avoid clutter)
- Most-recent reading prominently displayed below sparkline
- Empty-state ("No BP recorded in available history"): visible if zero observations returned

### 3.3 HbA1c trend (Tile 3)

```
┌─────────────────────────────────────────────────────────┐
│ HbA1c                                                   │
│   8.5 ●                                                 │
│    7  └●─────●─── target <7%                            │
│           ●                                             │
│        Q3'25  Q1'26  Q2'26                              │
│ Most recent: 7.1 % (Apr 2026)                           │
└─────────────────────────────────────────────────────────┘
```

- Sparkline of HbA1c values over last 4 results
- Target line at 7% — color-coded same as BP
- Quarter labels on x-axis (most lab schedules are quarterly)
- Empty state: visible if zero observations or DM not in active Problems

### 3.4 Active problems (Tile 4)

```
┌─────────────────────────────────────────────────────────┐
│ Active Problems                                         │
│   • Essential hypertension (I10) — recorded 2018-09-03  │
│   • Type 2 diabetes mellitus (E11.9) — 2018-09-03       │
│   • Hyperlipidaemia (E78.5) — 2020-04-22                │
└─────────────────────────────────────────────────────────┘
```

- List sorted by `recordedDate` ascending (oldest first — gives chronology)
- ICD-10-TM display + code in parentheses
- Empty state: "No active problems in circulatory/endocrine chapters" (Tile 4 is filtered; if patient has no HT/DM the demo is mis-targeted)

### 3.5 Active medications (Tile 5)

```
┌─────────────────────────────────────────────────────────┐
│ Active Medications                                      │
│   • Enalapril maleate 5mg BID    — taking               │
│   • Metformin HCl 500mg BID      — on-hold ⚠            │
│   • Atorvastatin Ca 20mg HS      — taking               │
└─────────────────────────────────────────────────────────┘
```

- Dose + frequency from `dosageInstruction` (request) or `dosage` (statement)
- Adherence flag (right side) only when `MedicationStatement.adherence.code` is non-`taking` — surface visually as warning glyph
- Dedupe by TMT code (same drug from request + statement → one row)
- Empty state: "No active medications"

## 4. Demo data — 5 fixture patients (Sprint 10)

5 patients seeded into HOSxP test DB (43Files schema), ingested via `mimir-43files-adapter` (Sprint 8 dep), available at mimir-fhir REST by demo time.

| ID | Name | Age | Profile |
|---|---|---|---|
| `uc1-p001` | สมชาย วงศ์มาลัย | 58M | HT only, stable on Enalapril, BP at goal |
| `uc1-p002` | สุดา จันทร์เพ็ญ | 67F | HT + T2DM + dyslipidemia, partial adherence (Metformin on-hold), HbA1c 8.2 — overlaps with UC2 P2 |
| `uc1-p003` | บุญส่ง กิตติชัย | 75M | Polypharmacy, well-controlled DM + HT, recent dose escalation — overlaps with UC2 P3 |
| `uc1-p004` | วรรณา สวัสดิ์ | 52F | T2DM only, newly diagnosed, no HT, HbA1c 9.1 (uncontrolled) — tests Tile 2 empty state |
| `uc1-p005` | ปรีชา รักษ์ดี | 64M | HT only, missed last 2 visits, stale data (>6 months since last BP) — tests stale-data display |

P002 and P003 are deliberate overlap with UC2 P2 and P3 to demonstrate that the same FHIR data drives both the structured-document use case (UC2) and the trend-view use case (UC1). One adapter ingest, two demos.

Fixture scripts: `Mimir/scripts/demo-patients/uc1-*.sql` (or generated alongside UC2 fixtures from a single source).

## 5. Smart-on-FHIR launch contract

Per [ADR-018](../decisions/ADR-018-cds-cqm-as-eir-agent-family.md) Sprint 9 dependency. Launch URL pattern:

```
https://asgard.local/smart/launch?
  iss=https://openemr.local/apis/default/fhir&
  launch={launch-token}&
  view=uc1-htdm
```

Token introspection at OpenEMR returns the patient context. App fetches resources from `mimir-fhir` (which has the same data via 43Files adapter), not from OpenEMR directly — this keeps the FHIR R5 canonical store as single source of truth and isolates demo data quality from OpenEMR's R4 emit.

Scope requested: `patient/Patient.read patient/Observation.read patient/Condition.read patient/MedicationRequest.read patient/MedicationStatement.read`. No write scopes.

## 6. Acceptance tests for Sprint 10 demo

Per fixture (UC1 P001–P005):

1. Smart-on-FHIR launch from OpenEMR demo instance completes without error
2. All 6 FHIR queries return within 500ms p95 (parallel)
3. All 5 tiles render — empty-states explicitly shown where applicable
4. Patient name renders in Thai for fixtures with Thai script names; English for ASCII-only
5. BP / HbA1c target lines render at correct values
6. Adherence warning glyph visible exactly for P002 (Metformin on-hold)
7. Identifier slice CID + HN both visible (per ADR-020 D3)
8. Empty Tile 2 (BP) visible for P004 (DM-only newly diagnosed)
9. Stale-data display for P005 (last BP >6 months) — leading date prefix

Demo-level:

10. Tyr audit chain has one event per Smart-on-FHIR launch with: `tenant_id`, `patient_id_hash`, `app_id=uc1-htdm`, `query_count`, `total_latency_ms`
11. Demo recordable end-to-end without LLM dependency (UC1 is offline-safe)
12. Demo deck slide pair (paper chart → UC1 view) for clinician audience

## 7. Out of scope (deferred to Phase 2)

- Editable views (UC1 is read-only)
- Trend over more than 4 readings (Phase 2 expanded history view)
- Drug interaction warnings (UC2 surfaces these; UC1 keeps focus on adherence + dose)
- Risk scores (Framingham, ASCVD, etc. — Phase 2 CDS)
- Print-friendly format
- Multi-patient comparison view
- Mobile app (Phase 1 = web only, responsive layout)
- Authoring / clinician notes
- Specialty variants (cardio-only, endo-only — single combined view is sufficient for Phase 1)

## 8. Open questions

| # | Question | Owner | Decision needed by |
|---|---|---|---|
| Q1 | Charting library — vanilla SVG, Chart.js, or D3? | UI dev | Sprint 9 day 1 |
| Q2 | Target lines configurable per patient (e.g., elderly relaxed BP target) or globally fixed? | clinical advisor | Sprint 10 demo prep |
| Q3 | Should HbA1c tile suppress (return empty) when DM not in active Problems, or always show? | clinical advisor | Sprint 10 demo prep |
| Q4 | Color palette for at-goal vs above-goal — match OpenEMR theme or Asgard brand? | UI dev + brand | Sprint 9 |
| Q5 | Does UC1 share its 5 fixtures with the UC1 acceptance corpus in mimir-fhir tests, or stay demo-only? | demo lead | Sprint 8 fixture gen |

## 9. Comparison to UC2 and UC3

| Dimension | UC1 (this doc) | UC2 patient summary | UC3 paeds immunization |
|---|---|---|---|
| Output | UI tiles (HTML/SVG) | FHIR Composition JSON | UI + Immunization list + computed next-due |
| Reasoning layer | none | gemma-4-26b LLM via patient-summary skill | deterministic JS (vaccine-schedule logic) |
| MCP tools | 0 (REST only) | 5 | 0 |
| Eval harness | acceptance tests only | 3-layer (L1 + L2 LLM-judge + L3 human) | acceptance + schedule-correctness tests |
| Demo patients | 5 (UC1 P001–P005) | 4 (P0/P1/P2/P3) | 5 (kids at different ages) |
| Sprint dependencies | 8 (adapter) + 9 (Smart-on-FHIR) | 4 (Composition) + 7 (validator) + 9 (UI) + 10 (skill-loader) | 5 (Immunization) + 9 (Smart-on-FHIR) |

UC1 is the **shortest path to a clinician-visible demo** in Phase 1. If timeline pressure forces a cut, UC2 + UC3 are the candidates to slip — UC1 alone demonstrates the data plane works.

## Links

- [composition-uc2-patient-summary-spec.md](composition-uc2-patient-summary-spec.md) — sibling use case spec
- [mimir-fhir-phase-1-plan.md](mimir-fhir-phase-1-plan.md) Sprint 10
- [ADR-016 Asgard FHIR Profile Family](../decisions/ADR-016-asgard-fhir-profile-family.md)
- [ADR-019 Profile validation](../decisions/ADR-019-fhir-profile-validation-tightest-binding-wins.md)
- [ADR-020 43Files adapter](../decisions/ADR-020-43files-hosxp-fhir-adapter.md)