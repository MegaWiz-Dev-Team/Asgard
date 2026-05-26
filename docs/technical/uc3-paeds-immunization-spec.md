# UC3 — Paediatric Immunization View: Design Spec

**Status:** Draft (companion to Sprint 10 demo plan)
**Date:** 2026-05-27
**Owner:** paripol@megawiz.co
**Sprints affected:** 5 (Immunization resource), 9 (Smart-on-FHIR launch), 10 (demo + 5 child fixtures)

## Purpose

UC3 is the third Sprint 10 demo, alongside [UC1 OPD HT/DM follow-up](uc1-opd-htdm-followup-spec.md) (data view, no LLM) and [UC2 patient summary](composition-uc2-patient-summary-spec.md) (LLM-generated FHIR Composition). UC3 sits between the two in complexity: a **read-only UI view augmented by deterministic scheduling logic** — no LLM reasoning, but more than pure rendering.

For a paediatric patient, the app shows:

1. **Vaccines administered** — from `Immunization` resources
2. **Next-due vaccines** — computed deterministically from the patient's age + administration history against the Thai MOPH EPI 2024 schedule

The vaccine-schedule logic is **embedded JavaScript in the demo app**, NOT the full `vaccine-schedule` Layer 2 clinical module (that ships in Phase 2 with multi-source schedules, catch-up logic, contraindications, etc.). Phase 1's logic is intentionally simple: age + administered list → next-due list.

## 1. Scope

A Smart-on-FHIR app launched from OpenEMR for a paediatric patient. Single screen with three tiles:

| Tile | Source | Render |
|---|---|---|
| 1. Patient header | `Patient` (CID slice or HN, name, exact age, sex) | header with age formatted as `Yy Mm` (e.g., `2y 4m`) |
| 2. Vaccines administered | `Immunization` where `status=completed`, `patient={id}` | list grouped by visit date, with vaccine name + dose number |
| 3. Next-due vaccines | deterministic JS over schedule + administered history | list of vaccines due now or overdue, with target-age + days-late |

No interactive features beyond the read-only view. No edits, no contraindication logic, no parental consent capture, no catch-up algorithm beyond "if missed, flag as overdue."

## 2. Data contract — mimir-fhir REST queries

```
GET /fhir/Patient/{id}
GET /fhir/Immunization?patient={id}&status=completed&_sort=date
```

That's it. Two queries on launch. Patient identifier slices per [ADR-020](../decisions/ADR-020-43files-hosxp-fhir-adapter.md) D3. Immunization resources per Asgard FHIR Profile (Sprint 5 work — see ADR-006 Amendment 1 +Immunization).

Token budget: not applicable. p95 fetch budget ≤300ms.

## 3. Thai MOPH EPI 2024 schedule reference

The schedule used by the demo. Hardcoded as a JS constant `MOPH_EPI_2024_SCHEDULE` in the demo app — NOT pulled from a FHIR `ImmunizationRecommendation` resource (Phase 2). Sprint 10 demo prep must verify the schedule values below against the current MOPH publication.

> ⚠️ **The values below are illustrative for design discussion. Demo lead must verify against the latest MOPH publication before fixture generation. Schedule changes are non-breaking — only the JS constant updates.**

| Age (target) | Vaccines | Notes |
|---|---|---|
| Birth | BCG, HBV-1 | given at delivery hospital usually |
| 2 months | DTP-HB-Hib-1, OPV-1, RV-1 | |
| 4 months | DTP-HB-Hib-2, OPV-2, RV-2 | |
| 6 months | DTP-HB-Hib-3, OPV-3 | (RV may be 3rd dose per brand) |
| 9 months | MMR-1, JE-1 | |
| 12 months | JE-2 | |
| 18 months | DTP-4, OPV-4 | |
| 2.5 years | JE-3 | |
| 4–6 years | DTP-5, OPV-5, MMR-2 | school-entry catch-up window |
| 11–12 years | dT-5, HPV (girls) | adolescent boosters |

Antigen codes per Thai MOPH coding standard (system URL TBD in ADR-016 v1.1 follow-up). Display names in Thai for Thai patients, English for others (per UC2 §language rule).

## 4. Vaccine-schedule logic (deterministic JS)

```js
function computeNextDue(patientAgeMonths, administered) {
  const dueList = [];
  for (const [ageMonths, vaccines] of Object.entries(MOPH_EPI_2024_SCHEDULE)) {
    const targetAge = parseFloat(ageMonths);
    if (patientAgeMonths >= targetAge) {
      for (const vaccine of vaccines) {
        const alreadyGiven = administered.some(imm =>
          imm.vaccineCode === vaccine.code && imm.doseNumber >= vaccine.doseNumber
        );
        if (!alreadyGiven) {
          dueList.push({
            ...vaccine,
            targetAgeMonths: targetAge,
            daysOverdue: Math.floor((patientAgeMonths - targetAge) * 30.44),
            status: patientAgeMonths > targetAge + 1 ? "overdue" : "due-now"
          });
        }
      }
    }
  }
  return dueList.sort((a, b) => a.targetAgeMonths - b.targetAgeMonths);
}
```

Logic rules:

1. A vaccine is "due now" if patient age has reached its target age within ±1 month
2. A vaccine is "overdue" if patient age exceeds target age by more than 1 month
3. A vaccine is hidden if patient age has not yet reached target age (no preview of future)
4. A vaccine is hidden if already administered with sufficient dose number
5. Sort by target age ascending (earliest catch-up first)

No contraindication logic. No catch-up acceleration. No live vs killed spacing rules. All Phase 2.

## 5. UI component spec

### 5.1 Patient header (Tile 1)

```
┌─────────────────────────────────────────────────────────┐
│ น้อง ฟ้าใส ภัทรกุล  ♀ 2y 4m  HN P-A23-4567               │
└─────────────────────────────────────────────────────────┘
```

- Age formatted `Yy Mm` (e.g., `0y 6m`, `2y 4m`, `5y 11m`)
- For infants <2 months, render `Wm Dd` (weeks + days)
- Sex glyph: ♂ / ♀
- HN visible; CID hidden for paediatric patients under MOPH PDPA guidance unless explicitly required

### 5.2 Vaccines administered (Tile 2)

```
┌─────────────────────────────────────────────────────────┐
│ Administered                                            │
│   Birth (2024-01-15)                                    │
│      • BCG                                              │
│      • HBV-1                                            │
│   2m (2024-03-15)                                       │
│      • DTP-HB-Hib-1                                     │
│      • OPV-1                                            │
│      • RV-1                                             │
│   ...                                                   │
└─────────────────────────────────────────────────────────┘
```

- Grouped by visit date (one heading per `Immunization.occurrenceDateTime` calendar day)
- Within group, sorted by `vaccineCode` display name
- Age at administration shown in heading (computed from `Patient.birthDate` and `occurrenceDateTime`)
- Empty state: "No immunizations recorded" — visible if zero results returned

### 5.3 Next-due vaccines (Tile 3)

```
┌─────────────────────────────────────────────────────────┐
│ Due / Overdue                                           │
│   ⚠ JE-3 — target 2.5y, overdue by 18 days              │
│   ● DTP-4 — due now (target 1.5y)                       │
│   ● OPV-4 — due now (target 1.5y)                       │
└─────────────────────────────────────────────────────────┘
```

- Sort: overdue first (descending by days-late), then due-now
- Status glyph: `⚠` for overdue, `●` for due-now
- Empty state: "All scheduled vaccines for this age are administered" (positive confirmation)

## 6. Demo data — 5 fixture children (Sprint 10)

5 children at different ages seeded into HOSxP test DB `EPI` table, ingested via `mimir-43files-adapter` (ADR-020 D2 Tier 3 — EPI → Immunization). Each fixture exercises a specific scenario.

| ID | Name | Age | Profile |
|---|---|---|---|
| `uc3-c001` | น้อง ฟ้าใส | 2m | newborn; only birth-dose vaccines administered, due for 2m batch (DTP-HB-Hib-1, OPV-1, RV-1) |
| `uc3-c002` | น้อง ภูผา | 6m | on-schedule; all expected doses administered through 4m visit, due for 6m batch |
| `uc3-c003` | น้อง ดาว | 1y | mild lag; missed 9m visit, MMR-1 + JE-1 now overdue by ~3 months |
| `uc3-c004` | น้อง ปริม | 2y 4m | overdue; missed 18m + 2.5y visits, multiple overdue (DTP-4, OPV-4, JE-3) |
| `uc3-c005` | น้อง ศิวกร | 5y | catch-up due; school-entry window, DTP-5 + OPV-5 + MMR-2 due now |

Fixture scripts: `Mimir/scripts/demo-patients/uc3-*.sql` (or shared generator with UC1/UC2).

## 7. Acceptance tests for Sprint 10 demo

Per fixture (uc3-c001 to c005):

1. Launch + 2 queries return within 300ms p95
2. Patient header renders age in correct `Yy Mm` / `Wm Dd` format
3. Tile 2 shows administered vaccines grouped by visit date, correct order
4. Tile 3 next-due computation matches expected fixture-defined list (golden corpus for vaccine logic)
5. Overdue glyph (⚠) visible exactly when `daysOverdue > 30`
6. CID slice hidden per paediatric privacy default; HN visible
7. Thai vaccine display names render in Thai script for fixtures with Thai patient names

Vaccine-schedule logic specific tests (golden corpus, runs in JS unit test):

8. `computeNextDue(2, [])` returns `[BCG, HBV-1]` (2-month-old with no vaccines — birth doses overdue)
9. `computeNextDue(12, all-through-9m)` returns `[JE-2]` (12-month-old on-schedule)
10. `computeNextDue(36, none)` returns the cumulative catch-up list through 2.5y
11. Already-administered vaccines never appear in due list (dedup by `vaccineCode` + `doseNumber`)
12. Future-age vaccines never appear (e.g., 11y-12y HPV not shown for 5y patient)

Demo-level:

13. Tyr audit event per launch with `app_id=uc3-paeds-immunization`, patient hash, query count
14. Demo recordable offline (no LLM dep)
15. Demo deck slide pair (paper EPI book → UC3 view) for paediatric clinician audience

## 8. Out of scope (deferred to Phase 2 / vaccine-schedule Layer 2 module)

- Catch-up acceleration logic (minimum intervals between doses)
- Live/killed vaccine spacing rules
- Contraindication detection (immunocompromised, allergy history)
- Parental consent workflow
- Vaccine inventory + lot tracking
- Multi-schedule comparison (MOPH EPI vs WHO vs ACIP)
- Adverse event reporting (AEFI)
- FHIR `ImmunizationRecommendation` resource generation (Phase 2 — once we have a richer logic engine, the recommendation becomes a real FHIR resource, not embedded JS)
- Reminder + SMS to parents (Phase 3)
- Travel vaccine recommendations
- Adolescent / adult vaccines beyond schedule
- HPV for boys (currently Thai MOPH girls-only — track MOPH policy update)

## 9. Open questions

| # | Question | Owner | Decision needed by |
|---|---|---|---|
| Q1 | Verify the exact MOPH EPI 2024 schedule values against latest MOPH publication | clinical advisor (paediatrician) | Sprint 10 demo prep |
| Q2 | Coding system for vaccine codes — MOPH antigen code vs CVX vs SNOMED — which is canonical in Asgard FHIR Profile? | ADR-016 v1.1 follow-up | Sprint 5 (Immunization resource) |
| Q3 | Should JE-2 → JE-3 spacing be hardcoded (per current schedule rules) or just age-based? Choosing age-based loses minimum-interval safety but keeps logic simple. | clinical advisor | Sprint 10 demo prep |
| Q4 | If a vaccine was given but at the wrong age (e.g., MMR-1 at 6m instead of 9m — too early), do we count it? Current logic: yes, count it (don't second-guess records). | clinical advisor | Sprint 10 demo prep |
| Q5 | Display Thai vs English vaccine names — match patient Patient.name language per UC2 §language rule, or clinician browser preference? | UI dev + clinical advisor | Sprint 10 demo prep |

## 10. Comparison to UC1 and UC2

| Dimension | UC1 (HT/DM) | UC2 (patient summary) | UC3 (this doc) |
|---|---|---|---|
| Output | UI tiles | FHIR Composition JSON | UI tiles + computed-list tile |
| Reasoning | none | gemma-4-26b LLM | deterministic JS (~50 LOC) |
| MCP tools | 0 | 5 | 0 |
| Resources fetched | Patient + Observation + Condition + MedicationRequest + MedicationStatement | full Bundle | Patient + Immunization |
| Eval | acceptance + UI | 3-layer + LLM judge + human | acceptance + JS-logic golden corpus |
| Demo patients | 5 adults | 4 fixtures (P0/P1/P2/P3) | 5 children |
| Sprint deps | 8 + 9 | 4 + 7 + 9 + 10 + skill-loader | 5 + 9 |

UC3 is the **shortest path to a paediatric demo** in Phase 1 — proves Immunization resource + EPI ingest + schedule logic all wire correctly. If demo slot pressure forces a cut, UC3 is the lowest-risk to ship because it has no LLM dependency and uses ~50 lines of deterministic JS.

## Links

- [composition-uc2-patient-summary-spec.md](composition-uc2-patient-summary-spec.md) — sibling use case
- [uc1-opd-htdm-followup-spec.md](uc1-opd-htdm-followup-spec.md) — sibling use case
- [mimir-fhir-phase-1-plan.md](mimir-fhir-phase-1-plan.md) Sprint 10
- [ADR-016 Asgard FHIR Profile Family](../decisions/ADR-016-asgard-fhir-profile-family.md)
- [ADR-020 43Files adapter — EPI table](../decisions/ADR-020-43files-hosxp-fhir-adapter.md)
- Thai MOPH EPI Programme — official publication TBD link in fixture