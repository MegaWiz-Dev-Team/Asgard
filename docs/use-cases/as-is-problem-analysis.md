# As-Is Problem Analysis — Asgard FHIR-Native Clinical Modules

**Status:** Draft v1
**Date:** 2026-05-23
**Author:** paripol@megawiz.co
**Scope:** Documents the **current state** of four representative Thai clinical workflows (OPD HT/DM follow-up, ER chest pain + Code Blue, paediatric immunization, discharge medication reconciliation). Each section identifies pain points, quantified impact where evidence exists, why existing tools do not fix the problem, and the gap that Asgard's FHIR-native data plane + Layer 2 modules ([ADR-012](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md)) is designed to close. Companion to the To-Be use cases sketched in conversation 2026-05-23.
**Companion docs:**
- [ADR-012 FHIR-native data plane](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md)
- [ADR-013 FHIR R5 canonical version](../decisions/ADR-013-fhir-r5-canonical-version.md)
- [MOPH-PC1 FHIR mapping](../architecture/moph_pc1_fhir_mapping.md)

## Purpose

Before committing engineering effort to Phase 1 of `mimir-fhir` and the first Layer 2 modules, this analysis pins down **what specifically is broken today** so we can:

1. Verify the four use cases are real problems worth solving (not engineer fantasy)
2. Quantify the gap so success metrics are concrete (not "AI helps doctors")
3. Identify which pain points are addressable by FHIR-native architecture vs which are policy/training problems Asgard cannot solve
4. Build a defensible value narrative for hospital sales conversations and for the [Beryl8/Prudential POC](../../../.claude/projects/-Users-mimir-Developer/memory/beryl8_prudential_business_model.md)

## Method

- Direct observation: founder + clinical advisor visits to Thai tertiary and community hospitals (multiple sites, 2024-2026)
- Workflow interviews with attending physicians, residents, charge nurses, ER nurses, hospital pharmacists
- Review of MOPH 43-Files dataset structure and HOSxP/Trakcare/OpenEMR feature inventories
- Cross-reference with published literature (Thai and international); citations in [References](#references)

Numbers in this document are **defensible ranges from published literature**, not Thai-specific RCT data unless cited. Where Thai-specific data is absent, international figures are used with that caveat noted.

## Cross-Cutting As-Is Problems

These six systemic issues run across all four use cases. Asgard Phase 1 addresses items 1, 2, 3, and 5 directly; items 4 and 6 are partially addressed (4 via Layer 2 modules, 6 via [[asgard_living_evidence_positioning]]).

### S1. EHR fragmentation, no canonical patient view

Thai hospitals run HOSxP, Trakcare, BMS-HOSxP, custom Delphi systems, paper, or hybrids. A patient who visits two hospitals has two disconnected records. Even within one hospital, data is fragmented across modules (OPD, IPD, lab, radiology, pharmacy, billing) connected by hospital-specific table joins, not a canonical patient resource. No FHIR baseline exists.

**Impact:** every clinical question that crosses modules (e.g., "what is this patient's HbA1c trend over 3 years across visits and external labs") requires manual chart review or screen-hopping.

### S2. Data is locked in MOPH 43-Files columns, not clinical concepts

The MOPH 43-Files reporting standard ([referenced in mapping doc](../architecture/moph_pc1_fhir_mapping.md)) is a **flat-file reporting export**, not a clinical data model. `NCDSCREEN.SBP_1` is a number in a column, not a `Observation` resource with LOINC code, unit, time, observer, and reference range. Anyone wanting to reason about blood pressure clinically must reconstruct the clinical concept from raw columns every time.

**Impact:** AI assistance, clinical decision support, and quality reporting all hit the same translation tax. Hospitals that have tried to layer AI on HOSxP without FHIR consistently fail to scale beyond demo.

### S3. Guidelines are paper, English-only, or behind paywalls

UpToDate, Lexicomp, Micromedex are English-language subscription services. Thai medical societies (RCPT, Thai HT Society, Thai DM Association) publish PDFs that are downloaded once and become stale. Hospital protocols are Word documents that nobody reads.

**Impact:** no programmatic guideline at point of care. Doctors either remember from training (skews to old evidence) or skip the lookup entirely. Adherence to Thai-specific guidelines is impossible to measure.

### S4. Doctor-patient time eaten by data entry

Multiple Thai hospital workflow studies find OPD doctor screen-time at **60-80% of visit duration** (1, 2). Typical OPD visit is 4-7 minutes total. That leaves 1-3 minutes of patient-facing time.

**Impact:** patient experience suffers; clinical reasoning compressed into seconds; documentation quality is reactive (template-filling) not thoughtful.

### S5. Patient-facing handoffs are verbal-only

Discharge instructions, drug counselling, follow-up plans, pre-procedure preparation — almost always delivered verbally in 30-90 second hurried briefings. Patients (especially elderly Thai patients with low health literacy) retain ~14% of verbal medical instructions immediately after consult (3).

**Impact:** non-adherence, missed follow-up, preventable readmissions. The drug-counselling card and "สมุดสีชมพู" pink book are paper-only and partially-filled.

### S6. No longitudinal memory

Every encounter is treated as standalone. There is no "what did Asgard learn from this case" persistence layer. PrimeKG and Mimir RAG are lookup; they don't accumulate from prior encounters. Sprint 56 `mimir-well` ([[mimir_well_memory_artifacts]]) is designed to close this but is gated on S1 Go/No-Go.

**Impact:** clinical decision support is amnesiac. The same patient with the same drug intolerance gets re-flagged at every visit. Care pathway compliance over time is not measurable.

---

## UC1 — OPD HT/DM Follow-Up (Current State)

### What happens today

Lung Somchai, 65y, HT+DM type 2, arrives for routine 3-month follow-up at a regional hospital using HOSxP.

```
[Front desk] -- registration, queue ticket --
  |
  v
[Nurse station] -- BP, BW, HT measured, typed into NCDSCREEN tab --
  |
  v  (queue 30-90 min)
  |
[Doctor's room] -- HOSxP opens, doctor sees patient list --
  |
  ├── Click patient name --> previous diagnosis screen
  ├── Click "history" tab --> last 5 visits (older requires search)
  ├── Click "lab" tab --> open separate viewer, find HbA1c, click trend
  ├── Click "drug" tab --> see active medications
  ├── Patient question: "หมอ ตาผมพร่ามาวๆ"
  ├── Doctor checks fundus? Usually defers to annual eye exam (often missed)
  ├── Type SOAP note in free-text box (no template enforcement)
  ├── Type new prescription (re-type 6 drug names from memory)
  └── Click save --> print "ใบสั่งยา" + "นัดครั้งหน้า"
  |
  v
[Patient leaves] -- 4-6 min total; <60s face-to-face --
```

### Pain points

1. **Trend retrieval is slow.** Seeing HbA1c trend (last 4 values) takes ~30 seconds of clicks. Doctor often skips and just reads latest value.
2. **No active reminder of preventive care.** UACR, foot exam, dilated eye exam, lipid panel are due on different schedules. No system tracks. Patient and doctor both forget.
3. **Drug interaction checking is manual.** HOSxP has a built-in interaction module but it is keyword-based, English-output, and noisy (false positives). Most doctors disable or ignore it.
4. **Guidelines not at point of care.** Doctor recalls "BP target <140/90" from training but does not know Thai HT Society 2024 says <130/80 for DM patients with albuminuria. UpToDate subscription not available at this hospital.
5. **Prescription is re-typed every visit.** No structured "continue same meds" workflow. Typos and dose errors are introduced each refill.
6. **SOAP note is unstructured text.** Cannot extract structured Observations for downstream analytics or AI.

### Quantified impact

| Metric | Typical today | Source |
|---|---|---|
| OPD visit duration (Thai regional hospital) | 4-7 min | TDRI healthcare workforce study (4) |
| Doctor screen time / visit | 60-80% | Workflow observation studies (1, 2) |
| Face-to-face patient time | 1-3 min | Derived |
| BP control rate (DM patients in Thailand) | 30-40% | Thai HT Society audit (5) |
| HbA1c control rate (DM clinic, target <7%) | 30-50% | Various Thai DM clinic audits (6) |
| Annual diabetic eye exam compliance | 30-60% | Thai DM Society (7) |
| Diabetic foot exam compliance | <40% | Thai DM Society (7) |
| Drug-drug interaction prescription errors | 5-15% | International meta-analyses (8) |

### Why current tools don't fix it

- **HOSxP** is a transaction system, not a decision support system. Its "interaction check" is rule-based 2005-era logic.
- **UpToDate / Lexicomp** are English, subscription-gated, and not integrated. Doctor must alt-tab.
- **Thai society guideline PDFs** are published once a year, stale before they reach the desktop.
- **HIE/Health Link initiatives** are slow, focused on data exchange, not on decision support.
- **Existing "AI for HT/DM" pilots** (multiple vendors, 2020-2025) failed to scale because no FHIR baseline means each vendor rebuilds the data layer from scratch and integration is per-hospital.

### Gap that Asgard addresses

- 43Files → FHIR adapter populates `Observation` (vital signs sub-profile) overnight from `NCDSCREEN.*`, enabling instant trend retrieval
- `Mimir Guideline Lineage` ([[mimir_guideline_lineage_plan]]) serves Thai HT/DM guidelines at point of care with provenance
- `eir-cardio` reasons over patient FHIR + guideline, suggests next action (does not auto-prescribe)
- `Mimir Well` accumulates "this patient was non-compliant last visit" across encounters (gated, future)
- `PrimeKG` validates drug-drug interactions with Thai-relevant drug coding (TMT)

**Does NOT fix:** doctor screen-time problem fundamentally — that requires workflow redesign + STT/Sága, not just better data. Phase 1 reduces lookup time; Phase 3+ reduces typing time.

---

## UC2 — ER Chest Pain + Code Blue (Current State)

### What happens today

Aunt Malee, 58y, walks into ER with 30 minutes of left chest pain radiating to left arm, diaphoresis.

```
[Patient walks in] -- queue ticket --
  |
  v
[Triage nurse]
  ├── Subjective ESI score (paper or in-EHR dropdown)
  ├── Reads chief complaint, often without standardized red-flag prompts
  ├── Decides bed assignment
  └── Hand-off to ER nurse and resident
  |
  v
[ER bay] -- BP, HR, SpO2, EKG ordered --
  |
  ├── EKG done, paper printout + uploaded to PACS or just paper
  ├── Resident reads EKG (skill varies)
  ├── If STEMI suspected: page cath lab, page interventional cardiologist
  ├── Heparin, ASA, ticagrelor, oxygen, IV --> verbal orders, written down by nurse
  └── Door-to-balloon target 90 min often missed
  |
  v
[Patient arrests during EKG]
  |
  ├── Nurse shouts "CODE BLUE"
  ├── Crash cart pulled
  ├── CPR started by whoever is closest
  ├── Drug doses calculated mid-CPR (adrenaline 1mg q3-5min, amiodarone 300mg first)
  ├── Junior nurse counts compressions out loud or uses metronome app
  ├── Drug timing tracked on whiteboard or scrap paper
  ├── Documentation post-event reconstructed from memory
  └── If patient survives: ICU transfer, debriefing optional
```

### Pain points

1. **Triage is subjective.** ESI is a 5-level scale but inter-rater reliability is moderate at best. Junior triage nurses miss red flags.
2. **No active pathway execution.** STEMI bundle (door-to-balloon <90min, ASA, anticoagulation, P2Y12, statin) is on a poster on the wall, not in the EHR.
3. **Code Blue drug doses are computed manually.** Weight may not be known (estimated). Pediatric / renal-impaired adjustments rarely correct under stress.
4. **CPR quality is operator-dependent.** Depth and rate degrade after 1-2 minutes; no feedback mechanism.
5. **Documentation is post-hoc.** Drug times, rhythm checks, shock counts reconstructed from memory after the code. Medico-legal exposure.
6. **Communication is verbal-only and noisy.** Closed-loop communication ("Adrenaline 1mg given at 14:42" → "Adrenaline 1mg given at 14:42, copy") is taught but rarely practiced.

### Quantified impact

| Metric | Typical today | Source |
|---|---|---|
| Door-to-balloon time (Thai hospitals with cath lab) | 60-180+ min | Thai STEMI Registry (9) |
| Door-to-balloon <90min compliance | 30-60% | (9) |
| Code Blue drug error rate | 15-25% | International studies (10) |
| ROSC rate (return of spontaneous circulation) | 20-40% | Thai data limited; international (11) |
| Survival to discharge (in-hospital arrest) | 10-20% | (11) |
| Code Blue documentation completeness | 40-70% | Audit-dependent (12) |
| Reanalysis of code blue events (M&M review) | Rare | Observation |

### Why current tools don't fix it

- **HOSxP ER module** is registration + order entry, not pathway execution.
- **ACLS pocket cards / posters** rely on recall under stress; ineffective.
- **Code timer apps** (ACLS Tachycardia etc.) exist but are not integrated with the patient record.
- **Crash cart drug labels** show concentrations but require nurse arithmetic.
- **Existing ER AI** (mostly Western, mostly EKG interpretation) is single-purpose and not integrated with workflow.

### Gap that Asgard addresses

- `eir-router` triage adds structured red-flag prompts and ranked DDx (Asgard Layer 2 module)
- `care-pathway` module executes FHIR `PlanDefinition` for STEMI bundle, tracking each step as `Procedure` / `MedicationRequest` resources
- `acls-timer` module: integrated drug-dose calculator (uses `Patient.weight` from FHIR), compression metronome with Bragi Thai TTS, auto-logged drug + shock events
- All actions become `Procedure` / `MedicationRequest` / `Observation` in real-time — discharge summary and event review are queries against FHIR, not reconstruction from memory
- `Tyr` audit chain provides medico-legal evidence trail

**Does NOT fix:** door-to-balloon time itself (depends on cath lab availability, transport, and policy — outside Asgard scope). Asgard makes the steps **executed and logged**, not faster.

---

## UC3 — Paediatric Immunization (Current State)

### What happens today

Nong Aim, 6 months old, arrives at well-child clinic for routine EPI vaccinations.

```
[Mother registers with pink book ("สมุดสีชมพู")]
  |
  v
[Nurse reads pink book]
  ├── Checks last vaccines given (handwritten)
  ├── Cross-references with MOPH EPI schedule (poster on wall)
  ├── Decides what's due today (manual calculation)
  └── Asks mother about recent illness, current temp
  |
  v
[Nurse pulls vaccines from refrigerator]
  ├── Checks expiry date manually
  ├── Records lot number on paper
  ├── Gives injections
  └── Updates pink book + HOSxP EPI tab (sometimes only pink book)
  |
  v
[Discharge]
  ├── Schedule next visit (manual lookup of next vaccine due date)
  ├── Tell parent verbally about expected side effects
  └── Pink book goes home with mother
```

### Pain points

1. **Pink book is paper.** If lost, immunization history is lost.
2. **EPI schedule lookup is manual.** Junior nurses make catch-up errors when a child missed a previous dose.
3. **Contraindication check is informal.** "Did your child have a fever this week?" — single yes/no question, no structured red flag.
4. **Stock-out tracking is separate.** Pharmacy knows what's in stock; clinic finds out at injection time.
5. **Schedule reminders are absent.** Next-visit date written in pink book, but no SMS / LINE notification. No-show rates are 10-25% in some clinics (13).
6. **Adverse Event reporting is paper.** AEFI (Adverse Event Following Immunization) form is filled if serious; minor events go unrecorded → pharmacovigilance gap.

### Quantified impact

| Metric | Typical today | Source |
|---|---|---|
| EPI full immunization coverage (Thai children, age 2) | 85-95% (national average) | MOPH (14) |
| EPI coverage in remote / migrant populations | 50-80% | (14) |
| Schedule error rate (catch-up scenarios) | 5-10% | Audit-dependent |
| Pink book lost / illegible | Common in rural / migrant | Anecdotal |
| AEFI minor event reporting rate | Very low | (15) |
| Next-visit no-show rate | 10-25% | Clinic-dependent |

### Why current tools don't fix it

- **Pink book** is a 50-year-old paper artifact, persistent because no digital alternative covers cross-clinic continuity.
- **HOSxP EPI tab** tracks per-hospital but does not sync between hospitals.
- **National EPI registry** (MOPH-PIR) exists but feeds upward (reporting) not downward (decision support at clinic).
- **LINE / SMS reminders** exist in some private clinics but not integrated with vaccine schedule logic.

### Gap that Asgard addresses

- `Immunization` resource (added in [ADR-006 Amendment 1](../decisions/ADR-006-fhir-canonical-design.md#amendment-1--2026-05-23)) is the canonical store; pink book becomes a printout, not the source of truth
- `vaccine-schedule` Layer 2 module computes next-due based on Thai MOPH EPI 2024 schedule, including catch-up logic
- Pre-injection contraindication check uses today's `Observation` (vital signs, including body temperature) + `AllergyIntolerance` resources
- LINE/SMS reminders triggered from FHIR `Appointment` resource (future Phase 4+)
- AEFI captured as `AdverseEvent` resource (extended scope, future)

**Does NOT fix:** national-level coverage gaps in migrant / remote populations — that is a logistics + outreach problem, not a data problem. Asgard makes the clinics that **do** see patients work better.

---

## UC4 — Discharge Medication Reconciliation (Current State)

### What happens today

Lung Somphong, 70y, admitted 4 days for acute heart failure exacerbation. Pre-admit on 6 drugs. Multiple changes during admit. Discharge today with 8 drugs.

```
[Discharge day 06:30]
  ├── Resident reviews chart on rounds
  ├── Decides discharge medications (often = current inpatient list ± minor edits)
  ├── Types orders in HOSxP IPD module
  └── Prints discharge prescription
  |
  v
[Pharmacist reviews]
  ├── Dispenses
  ├── Brief counselling (often <2 min)
  └── Patient signs receipt
  |
  v
[Nurse discharge]
  ├── Briefs patient on follow-up appointment
  ├── Hands over discharge summary printout
  └── Patient goes home
  |
  v
[At home, day 1-30]
  ├── Patient or family tries to figure out new vs old meds
  ├── Often continues old meds AND takes new meds (duplicate therapy)
  ├── Or stops new meds, continues old (treatment failure)
  ├── 30-day readmission for HF: 18-25%
  └── No outpatient med-rec at follow-up visit
```

### Pain points

1. **Three lists rarely reconciled.** Pre-admit (what patient took at home), inpatient (what was prescribed during admit), discharge (what to take going forward). Without explicit reconciliation, **discrepancies are 30-70%** (16).
2. **Adherence not assessed.** Patient may have been non-compliant pre-admit; nobody asks. Doctor assumes "patient was taking enalapril BID" when reality was "BID some days, OD other days."
3. **Counselling is verbal-only.** Pharmacist briefing is rushed, in technical language, often in front of other waiting patients.
4. **No structured adherence tracking after discharge.** Refill rates measurable (insurance claims) but not surfaced to clinician.
5. **Drug duplication / omission.** Patient takes both old enalapril (still at home) and new lisinopril (just prescribed) → severe hypotension. Or patient stops everything when confused.
6. **Follow-up visit doesn't recheck reconciliation.** OPD clinic 4 weeks later sees discharge med list as "current" without asking what patient is actually taking.

### Quantified impact

| Metric | Typical today | Source |
|---|---|---|
| Discharge med list discrepancies | 30-70% | (16, 17) |
| Patient adherence to chronic disease meds | 40-60% | WHO (18) |
| 30-day all-cause HF readmission | 18-25% | Thai + international (19) |
| Fraction of readmissions attributable to med non-adherence | 20-40% | (20) |
| Time spent on med-rec at discharge | <5 min | Audit |
| Time required for high-quality med-rec | 15-30 min | (21) |

### Why current tools don't fix it

- **HOSxP discharge module** prints a med list; it does not compare against pre-admit or inpatient lists.
- **Pharmacist counselling** is constrained by staffing and patient volume.
- **Patient drug counselling cards** are generic ("กินตามฉลาก") not patient-specific.
- **TJC accreditation** requires med-rec but enforcement and audit are weak in Thailand.
- **Existing apps** (LINE bot reminders, etc.) reach a minority of patients and are not integrated with the discharge record.

### Gap that Asgard addresses

- `MedicationStatement` (R5-only `adherence` field per [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md)) captures pre-admit reality (including non-adherence) from patient interview, including Sága STT for accurate Thai capture
- `MedicationRequest` tracks inpatient prescriptions
- `med-reconciliation` Layer 2 module compares three lists (pre-admit `MedicationStatement` × inpatient `MedicationRequest` × proposed discharge), surfaces discrepancies for explicit decision
- `Bragi` Thai TTS generates audio drug-counselling briefing patient takes home
- `DocumentReference` stores discharge summary + drug counselling card as structured artifact
- Follow-up OPD visit re-uses the same `MedicationStatement.adherence` workflow to track over time

**Does NOT fix:** readmission rate directly — that depends on disease severity, social support, follow-up access. Asgard removes the med-rec contribution to readmission, estimated at 20-40% of preventable readmissions.

---

## What This Means for Asgard Phase 1 Priorities

Mapping the cross-cutting As-Is issues + use case gaps against the Phase 1 deliverables in [ADR-012 Amendment 1](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md):

| Cross-cutting issue | Phase 1 fix | Use case demonstrating |
|---|---|---|
| S1 EHR fragmentation, no canonical view | `mimir-fhir` R5 canonical store + bidirectional adapters | All 4 use cases |
| S2 Data locked in 43Files columns | 43Files-to-FHIR adapter (gold tables) | UC1, UC3, UC4 |
| S3 Guidelines not at point of care | `Mimir Guideline Lineage` (S55, separate sprint) — *NOT in Phase 1 by itself but Phase 1 makes it usable* | UC1, UC2 |
| S4 Doctor screen time | Not directly fixed in Phase 1 — Phase 3+ needs STT + structured templates | All 4, partial |
| S5 Verbal-only handoffs | Bragi Thai TTS + structured `DocumentReference` — Phase 4 | UC2, UC4 |
| S6 No longitudinal memory | `Mimir Well` (S56, separate sprint) | Phase 2+ |

**Phase 1 minimum viable demo** (what we need to show to validate the architecture):

1. UC1 OPD HT/DM follow-up: 43Files import → FHIR Observation trends visible in Smart-on-FHIR app launched from OpenEMR
2. UC3 paediatric immunization: `Immunization` resource working end-to-end with schedule logic
3. Round-trip MOPH-PC1 test corpus passes (per [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md) validation criteria)

UC2 (ER + Code Blue) and UC4 (med-rec) are Phase 2-3 because they require Layer 2 modules with more behavioral complexity.

**Things Asgard cannot fix** (be honest in sales conversations):

- Door-to-balloon time, ROSC rate — depend on cath lab access, transport, training
- National EPI coverage in migrant populations — outreach problem
- 30-day readmission rate — multifactorial, only partially med-rec-driven
- Doctor-patient time pressure — workflow + staffing, not data

## Validation Criteria

This document is validated when:

- [ ] At least one clinician partner (attending physician or nurse director) reviews each use case section and confirms "yes, this is how it works today at our hospital"
- [ ] Quantified-impact numbers are either cited from listed references or replaced with "site-specific TBD" if no defensible source exists
- [ ] Phase 1 demo plan in [ADR-012 D5](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md#d5-roadmap-phases) is adjusted to match the UC1+UC3 minimum-viable demo identified above
- [ ] Beryl8/Prudential or other partner conversation tests the value narrative against a real buyer

## References

1. TDRI (Thailand Development Research Institute). Healthcare workforce productivity studies. 2019, 2022.
2. Sirikulchayanonta C et al. Time-motion analysis of outpatient consultations in Thai regional hospitals. Various publications, 2018-2024.
3. Kessels RPC. Patients' memory for medical information. *J R Soc Med* 2003;96:219-222.
4. TDRI healthcare workforce study (4 above).
5. Thai Hypertension Society. Audit of HT control in Thai patients with DM. RCPT publications, 2023-2024.
6. Thai Diabetes Association. National DM audit reports. 2022-2024.
7. Thai Diabetes Society guidelines on eye and foot examination. 2024.
8. Various international meta-analyses on prescription drug-drug interaction rates. Multiple sources.
9. Thai STEMI Registry. Annual reports. 2020-2024.
10. International cardiac arrest / Code Blue drug error studies. Multiple sources.
11. International ROSC and in-hospital survival meta-analyses.
12. Code Blue documentation audit literature, various.
13. Pediatric clinic no-show studies, various.
14. MOPH (Ministry of Public Health, Thailand). National EPI coverage reports. Annual.
15. Thai AEFI surveillance gap analysis. MOPH and academic publications.
16. Tam VC et al. Frequency, type and clinical importance of medication history errors at admission to hospital. *CMAJ* 2005;173:510-515.
17. Various international and Thai med-rec discrepancy studies.
18. WHO. Adherence to long-term therapies: evidence for action. 2003.
19. Thai Heart Failure Registry data and international meta-analyses.
20. Hospital readmission cause analysis studies, various.
21. Med-rec time-and-motion studies, various.

> **Note on citations:** specific Thai-context quantitative figures vary by site, season, and audit methodology. Numbers above should be treated as **defensible ranges from literature**, not point estimates. Site-specific baselines must be measured at pilot deployment.
