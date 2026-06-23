# Asgard Nótt (Sleep Test) — Execution Plan
<!-- Product = Nótt; infra = mimir-sleep (engine) + eir-sleep (agent). -->


**Owner:** paripol@megawiz.co
**Date:** 2026-06-09
**Decision of record:** [ADR-025](../decisions/ADR-025-sleep-test-eir-resmed-ingestion.md)
**Principles:** Rust-First · FHIR R5 canonical · PHI = Skuggi+Tyr+consent first-class · backup-before-state-change · TDD · no new Norse (extend families) · credentials in Vault only

---

## Architecture

```
Telemed encounter → doctor obtains consent → FHIR R5 Consent recorded
   ⇒ Admin-portal pull button UNLOCKS (disabled without consent-on-file)
Admin clicks (one patient at a time; NO cron/cohort)
   └─> A2A → MegaCare GCP (Cloud Tasks `airview-raw-signals`, no scheduler)
        └─> Playwright worker (intercept-network-response, PR#208; AirView creds ON MEGACARE)
             └─ download raw signals (EDF/EDF+ or ResMed .mmrx — TBD GATE b) from diagnostic/signals
        └─> A2A transfer raw blob → Asgard MinIO `asgard-sleep-raw`
   Asgard side:
        └─> mimir-sleep (Rust): parser+sentinel/SQI → FEATURE ENGINE (HB/AHI/central%/CSR/ODI/T90) → FHIR R5 map
             │   DUAL-SINK:
             ├─ Clinical → mimir-fhir (R5): Patient / DiagnosticReport / Observation / Consent
             │            + raw blob → MinIO (DocumentReference)
             └─ Analytics → mimir-lab (asgard_analytics)   [only if consent covers analytics]
   Consent gate (trigger + analytics-registration) · Skuggi · Tyr audit · tenant asgard_medical
   eir-sleep agent = clinical surface (reads the FHIR record)
```

- **Acquisition** (scrape) is isolated so it can later be swapped for an official ResMed API without touching parse/map.
- **`mimir-sleep`** = new Mimir-family submodule (EDF parser + FHIR mapper). **`eir-sleep`** = existing agent variant (clinical reasoning), reads FHIR from mimir-fhir.

## Reusable building blocks (already in the stack)
- **chromiumoxide** (headless browser) — in the `ro-ai-bridge` workspace deps → the scraper is Rust-first.
- **Rust `edf` / `edf-reader` crate** — EDF/EDF+ parsing.
- **`bifrost-jobs`** — cron/triggered job runtime (admin-trigger + status UI pattern already exists).
- **mimir-fhir** (R5 store), **MinIO** (blobs, via mimir-lab::storage), **Vault/fafnir-vault** (creds), **Skuggi/Tyr** (PHI).

---

## Phases

### P0 — Two hard gates + foundations (block the LIVE scraper, not the offline core)
- [ ] **GATE (a): Confirm ResMed AirView ToS / legal** for scripted access (clinic's own account + own consented patients) — written sign-off. Consent does NOT settle this.
- [ ] **GATE (b): Probe AirView** — does `diagnostic/signals` actually let us download raw files, and are they **EDF/EDF+** or ResMed **`.mmrx`** (or both)? Determines the parser. (Manual probe by an authorised operator — not a blind fetch.)
- [ ] Consent model: **consent-at-telemed** → **FHIR R5 `Consent`**; admin button gated on consent-on-file; consent checked at trigger **and** analytics registration.
- [ ] Credential design: AirView session/creds in Vault (`fafnir-vault`); read at runtime, never logged.
- [ ] Draft the **Asgard sleep-study FHIR profile** (ADR-016 family) + LOINC/SNOMED code set for the feature-engine metrics (HB/AHI/central%/CSR/ODI/T90, leak, usage…).

### P1 — `mimir-sleep` crate: parser + feature engine (Rust, TDD) — **DOABLE NOW, no gates** (≈4–5 d)
- [ ] Scaffold `ro-ai-bridge/mimir-sleep` (own `[workspace]` like mimir-fhir/mimir-lab).
- [ ] **Canonical, vendor-/type-agnostic data model** (`SleepStudy` + `CanonicalChannel` + `SleepTestType` 1/2/3/4): `SignalReader` trait (EDF/EDF+ primary via `edf` crate; ResMed `.mmrx`=zip→EDF; future Philips/Nox adapters) + **channel-alias table** (vendor label→canonical) + **test-type capability** (mark each feature available/valid; Type1/2 add sleep-staged metrics). **TDD** on **public tutorial / de-identified** data — no AirView needed.
- [ ] **Port the Python prototype feature engine → Rust**: HB, AHI, central %, CSR, ODI, T90 (+ leak, usage). TDD each metric against the prototype's outputs on the same sample.
- [ ] **Phenotype classifier (deterministic, versioned)** — from event-type indices → primary class (Obstructive / Central-CSA / Mixed-Complex / Cheyne-Stokes / Hypopnea-predominant) + modifiers (Positional, Severe-hypoxemia) + severity. Label central-vs-obstructive "suspected" on HST. TDD on tutorial data.
- *This whole phase runs on tutorial data — start here regardless of the ResMed gates.*

### P2 — FHIR R5 mapping + DUAL-SINK persistence (≈3–4 d)
- [ ] Map → R5: Patient (match/create) · DiagnosticReport (sleep study) · Observation per feature (coded LOINC/SNOMED) · DocumentReference→MinIO for the raw blob · `Consent`.
- [ ] Validate against the sleep-study profile (ADR-019 tightest-binding).
- [ ] **Clinical sink** — ⚠️ `mimir-fhir` is datatypes-only (can't persist yet) → **interim: Bundle JSON → MinIO** + raw blob → MinIO (reuse `mimir-lab::storage`); swap to live mimir-fhir ingest at its Sprint 2–6. Idempotent per study.
- [ ] **Analytics sink** → `mimir-lab` (only when consent covers analytics).
- [ ] Tyr audit + Skuggi gate + consent check on every write.

### P3 — MegaCare-side extract + A2A transfer (≈4–5 d) — needs GATES (a)+(b)
- [ ] **MegaCare GCP** Cloud Tasks queue `airview-raw-signals` (no scheduler) + **Playwright** worker (intercept-network-response, reuse AirView-daily-sync PR#208 pattern). **AirView creds stay MegaCare-side** (not Asgard). Consent-gated, human-initiated, one patient at a time.
- [ ] Robust selectors + failure handling (UI-brittle); retries; **no creds in logs**.
- [ ] **A2A transfer** raw blob → Asgard MinIO `asgard-sleep-raw` → `mimir-sleep`. End-to-end: consented pull → dual-sink.
- [ ] ⚠️ serialize — one pull at a time.

### P4 — Admin-portal trigger + status (≈2–3 d)
- [ ] Admin-portal button (per patient) → enqueue `airview-pull` → job status (reuse Bifrost cron-monitor UI) + Tyr trail.
- [ ] Show last-pull time / result per patient.

### P5 — Analysis + clinical surface (≈3–4 d)
- [ ] Signals → `mimir-lab` for analysis (trend, events); structured Observations queryable.
- [ ] De-identified/aggregate path to `asgard_analytics` (ADR-024 bounded adapter) if cross-tenant analysis wanted.
- [ ] `eir-sleep` agent reads the FHIR record for clinical Q&A (local LLM only).

### P6 — KB-backed augmentation (targeted retrieval, NOT blanket grounding) (≈3–4 d)
`eir-sleep` tool allowlist = `search_clinical_kb` / `search_icd10` / `search_primekg` / `search_pubmed` (+ read FHIR), called on-demand. Decision stays deterministic (P1 classifier + decision table); KB is a citation/coding/comorbidity layer (per [[eir_kb_grounding_ab_result]] — no stacked grounding).
- [ ] **(a) Decision-support with citation** — each proposed pathway retrieves backing guideline/evidence (clinical-wisdom; pubmed: ASV-in-HFrEF SERVE-HF, Azarbarzin HB) → auditable recommendation.
- [ ] **(b) Auto-coding FHIR** — diagnosis + phenotype → ICD-10-TM (G47.3x) + SNOMED (OSA/CSA/CSR) from KB, not hardcoded.
- [ ] **(c) Patient education** — plain-language result for LINE summary / consent / report, grounded in clinical-wisdom, in the patient's language.
- [ ] (optional) new shared sleep-medicine KB (AASM scoring + ResMed device guidance) → register on `/api/v1/knowledge/shared` + UI.

**Total:** ~18–24 dev-days (after P0 legal sign-off). P1+P2 = offline core (EDF→features→FHIR, testable without the scraper); P3 live acquisition; P4 trigger; P5 analysis/viewer; P6 KB citation/coding/education.

---

## Risks
1. **ResMed ToS / scraper legality** — gating; confirm before P3.
2. **Scraper brittleness** — AirView UI changes break it; isolate acquisition; prefer official API if it appears.
3. **PHI** — Skuggi/Tyr/consent + Vault creds; de-identify before analytics.
4. **EDF variability** — vendor EDF/EDF+ quirks; validate against real (de-identified) samples early.
5. **Mac-mini load** — headless browser + EDF parse are heavy; serialize, don't run parallel pulls (kernel-panic rule).

## Definition of done (MVP = P1–P3)
Admin clicks pull for a patient → EDF fetched from AirView → parsed → stored as FHIR R5 (DiagnosticReport + Observations + raw-EDF DocumentReference) in mimir-fhir + MinIO, fully Tyr-audited, queryable by eir-sleep and mimir-lab.
