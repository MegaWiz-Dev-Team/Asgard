# ADR-025: Asgard Nótt — Sleep-Test Ingestion + Analysis (FHIR R5, no OpenEMR)

**Product name:** **Nótt** (Norse goddess of Night) — the Asgard sleep-test capability. *Product label only; infra keeps the family-naming rule:* engine = **`mimir-sleep`** (Mimir family), clinical agent = **`eir-sleep`** (Eir family — agent role, NOT OpenEMR).

**Status:** Proposed
**Date:** 2026-06-09
**Deciders:** paripol@megawiz.co
**Scope:** New sleep-medicine domain — patient record + CPAP/PSG signal ingestion + analysis
**Related:** ADR-012 (FHIR-native, no EHR replacement), ADR-013 (R5 canonical), ADR-014 (FHIR data-plane ownership = Mimir), ADR-016 (Asgard FHIR profile family), ADR-019 (profile validation), ADR-022 (Smart-on-FHIR launch), ADR-024 (asgard_analytics engine), [origin: sleep-clinic CPAP roots], [feedback: Tyr/Skuggi in every PII design], [feedback: no new Norse components]

> **Cross-session note — read [[eir_sleep_resmed_ingestion]] memory first.** This ADR is the single source of truth; it has been **reconciled with a parallel session that VERIFIED two facts that override the first draft:**
> 1. **`mimir-fhir` is datatypes-only today** (resources/REST/persistence commented out — Phase-1 Sprint-0). So the FHIR clinical sink **cannot ingest resources yet** → interim = store the **FHIR Bundle JSON + raw signal as a blob in MinIO**; full FHIR persistence waits for mimir-fhir Sprint 2–6. The **analytics sink (`mimir-lab`) IS ready**.
> 2. **Acquisition must run MegaCare-side, not Asgard.** AirView credentials/session live on the **MegaCare GCP Cloud Run** side; the pipeline spans both orgs, bridged by **A2A** ([[megacare_asgard_a2a_integration]]). Extraction = MegaCare **Playwright** worker (intercept-network-response pattern, per AirView-daily-sync PR #208) → A2A transfers the raw blob to Asgard → Asgard does decode/features/analysis. (So **not** an Asgard-side `chromiumoxide` job as the first draft assumed.)
>
> A **Python reference prototype already exists** at `/Users/mimir/Developer/time-series-tutorial` (`hst_to_fhir.py`, `hypoxic_burden.py`; 15 de-identified patients) — it is the **feature-engine spec to port to Rust `mimir-sleep`**. Highest-value metric per the prototype = **central-apnea fraction + Cheyne-Stokes (CSR)** (> Hypoxic Burden for treatment decisions). **Do not draft a second ADR — extend this one.**

## Context

Asgard began as sleep-clinic CPAP support. The raw diagnostic data lives in **ResMed AirView** (cloud), per-patient, on a **diagnostic signals** page
(`https://ap-airview.resmed.com/hst/patients/<uuid>/diagnostic/signals/`) as raw signal files — **EDF/EDF+ or ResMed proprietary `.mmrx`** (to be probed, §7) — waveforms (flow / pressure / SpO₂ / effort, etc.). The clinic wants to:

1. Bring that raw data into **Asgard's own store as the record of truth** for sleep.
2. **Trigger ingestion from the admin portal** (operator action, per-patient).
3. **Analyse** the signals (not just store them).

User direction (verbatim intent): *"make Eir the patient data store — a Sleep-Test-specific Eir; don't need OpenEMR; must support FHIR R5; want to analyse patient data too."*

ResMed offers no chosen official API/export here, so acquisition is an **authenticated-session scrape**. This is **PHI**, **ResMed-ToS-sensitive**, and needs careful credential handling.

## Decision

> **Sleep-Test Eir is a Smart-on-FHIR Layer-2 module over `mimir-fhir` (R5) — not OpenEMR. Acquire ResMed AirView EDF via an admin-triggered authenticated-session scrape job, parse + map to FHIR R5 in a new `mimir-sleep` submodule (raw EDF to MinIO), all PHI-gated, then analyse via `mimir-lab`.**

1. **Storage stays in the Mimir family (ADR-014).** "Eir as patient store" is realised as: the **FHIR R5 store IS `mimir-fhir`** (record of truth); **eir-sleep** (existing agent variant) is the clinical surface. **NOT** OpenEMR (departs from OpenEMR-backed `eir-gateway` for sleep); Eir does **NOT** own FHIR storage.
   - ⚠️ **Today `mimir-fhir` is datatypes-only — it cannot persist resources yet.** So the clinical sink is **interim**: emit the **FHIR R5 Bundle JSON** (Patient + DiagnosticReport + Observations + Consent) and store it **as a blob in MinIO** alongside the raw signal, until mimir-fhir gains resource/REST/persistence (its Sprint 2–6). Same R5 shape now → swap to live mimir-fhir ingest later with no remodelling.

2. **`mimir-sleep` engine — in its own `asgard-nott` repo** (Nótt is a separate product repo, not inside Mimir; the crate is still a Mimir-family data engine by role, no new Norse): Rust-first **signal parser** (EDF/EDF+; `.mmrx` decoder once §7 probe resolves) + sentinel filter (127 SpO₂ / 511 pulse) + signal-quality (SQI) + a **deterministic, versioned feature engine** (§4) + **sleep-study → FHIR R5 mapping**. **Port from the existing Python prototype** `/Users/mimir/Developer/time-series-tutorial` (`hst_to_fhir.py`, `hypoxic_burden.py`) — it is the feature-engine spec. Writes to the clinical + analytics sinks (§4); raw blob → **MinIO**.

3. **Ingestion = consent-gated, human-initiated, per-patient — NO scheduler/cron/cohort — and SPLIT across orgs.** Flow: doctor obtains consent during a **telemed** encounter → records a **FHIR R5 `Consent`** → the admin-portal **pull button unlocks only with consent on file** → admin clicks **one patient at a time** →
   - **Extract (MegaCare GCP side):** a Cloud Tasks queue (`airview-raw-signals`, no scheduler) → a **Playwright** worker (intercept-network-response pattern, per AirView-daily-sync PR #208) against AirView (`…/patients/<uuid>/diagnostic/signals/`); **AirView credentials/session live on the MegaCare side** (not Asgard). Resolve UUID via the short-hex→UUID path; idempotency on `airview_identity_id`.
   - **Transfer:** raw signal blob → **A2A bridge** ([[megacare_asgard_a2a_integration]]) → Asgard **MinIO `asgard-sleep-raw`** (encrypt in transit, Skuggi-gate, Tyr-audit).
   - **Decode (Asgard side):** `mimir-sleep` parses + features + maps.
   No automated/cohort sweep — each pull is a human action tied to a consented patient.

4. **Feature engine → DUAL-SINK.** Metrics (Rust port of the prototype): **HB (Hypoxic Burden, Azarbarzin 2019), AHI, ODI, T90, mean/nadir SpO₂, central-apnea fraction, CSR (Cheyne-Stokes)**. **Highest-value = central % + CSR** (flags patients who must NOT get plain CPAP → cardiac workup/ASV; > HB for treatment decisions). Two sinks:
   - **Clinical sink → FHIR R5 Bundle** (Patient + DiagnosticReport[LOINC 28633-6] + Observations + **`Consent`**; Asgard sleep-study profile, ADR-016/019). **Interim: Bundle JSON → MinIO** until mimir-fhir can persist (§1).
   - **Analytics sink → `mimir-lab`** (asgard_analytics): features Parquet via `register_dataset` — **gated by consent-for-analytics** (§5). **Join key = `DiagnosticReport.id`** carried as a column.

5. **PHI governance — consent is first-class.** Tenant = **asgard_medical**. A **FHIR R5 `Consent`** (captured at the telemed encounter) gates **two** points: (a) the **pull trigger** (button disabled without consent-on-file), and (b) **analytics registration** (data only enters the `mimir-lab` analytics sink if consent covers analytics use). **Skuggi** scan + **Tyr** audit on every ingest/read/export; Vault-held credentials; de-identify before any cross-tenant analytics use (ADR-024 bounded adapter).
   - **Consent ≠ ResMed ToS.** Patient consent (clinical/PDPA) authorises *us to hold/use their data*; it does **not** authorise *scripted access to ResMed's portal* — that is a separate **contractual ToS** question (see §7). Both must clear independently.

6. **Analysis.** Waveforms → **`mimir-lab`** (asgard_analytics engine) for signal analysis; structured Observations queryable via FHIR + `mimir-lab`.

7. **Two hard gates before the live scraper can be built** (both are non-code; neither blocks the offline core in §2/§4):
   - **(a) ResMed AirView ToS / legal** for automated/scripted access — confirm in writing (clinic accessing its own consented patients on its own account — likely OK, but consent does not settle this; §5).
   - **(b) Probe the actual raw format AirView serves** — does the `diagnostic/signals` page actually let us download raw signal files, and are they **EDF/EDF+** or **ResMed proprietary `.mmrx`** (or both)? This determines the parser. The `mimir-sleep` parser must handle whatever AirView serves; **don't assume plain EDF**.
   Scraper is **UI-brittle**; if an official ResMed API/export appears, swap the acquisition stage only (`mimir-sleep` parse/map is unaffected).

8. **KB-backed augmentation — TARGETED retrieval, NOT blanket grounding.** Per [[eir_kb_grounding_ab_result]] (stacking shared KBs into a chat agent hurt quality −16pp), the treatment decision stays **deterministic** (the phenotype classifier + decision table, §below). Shared KBs add three things, pulled **on-demand** by `eir-sleep` via the existing Hermodr KB tools (`search_clinical_kb` / `search_icd10` / `search_primekg` / `search_pubmed`) — never stacked into every prompt:
   - **(a) Decision-support with citation** — for each proposed pathway, retrieve the backing guideline/evidence (clinical-wisdom sleep/CPAP/cardiology; pubmed e.g. ASV-in-HFrEF SERVE-HF caution, Azarbarzin Hypoxic Burden). The **rules decide; the KB cites** → auditable, clinician-trusted.
   - **(b) Auto-coding FHIR** — map diagnosis + phenotype → **ICD-10-TM** (G47.3x) + **SNOMED** (OSA / CSA / Cheyne-Stokes) from icd10-th + SNOMED KBs → FHIR Observation/Condition codes, not hardcoded.
   - **(c) Patient education** — generate a plain-language result explanation (LINE summary / consent / report) grounded in clinical-wisdom, in the patient's language.
   The decision NEVER comes from the LLM/KB alone — KB is a **citation/coding/comorbidity** layer over deterministic rules. `eir-sleep` tool allowlist = `search_clinical_kb`, `search_icd10`, `search_primekg`, `search_pubmed` (+ read FHIR). A new sleep-specific shared KB (AASM scoring, ResMed device guidance), if added, must register on `/api/v1/knowledge/shared` + a UI page (shared-knowledge-surface rule).

### Phenotype classifier + treatment selection (deterministic)
From the AirView-scored event types (obstructive / central / mixed / unclassified AI, HI, CSR%, supine vs non-supine AHI, ODI, T90):
- `central_fraction = central_AI / AI`; `positional_ratio = supine_AHI / nonsupine_AHI`.
- **primary class:** CSR-flagged/high → *Cheyne-Stokes / central (cardiac)*; `central_fraction ≥0.5` (+CAI≥5) → *Central-predominant (CSA)*; significant mixed → *Mixed/Complex*; `AI ≥ HI` obstructive-dominant → *Obstructive OSA*; `HI ≫ AI` → *Hypopnea-predominant*.
- **modifiers:** *Positional* (`positional_ratio ≥2` & low non-supine), *Severe hypoxemia* (high T90/ODI); **severity** by AHI (5/15/30).
- **pathway (HITL — eir-sleep proposes, doctor decides):** Obstructive→CPAP/APAP; Central/CSR→cardiology workup + ASV/BiPAP-ST (NOT plain CPAP); Mixed→trial CPAP, watch treatment-emergent→ASV; Positional→positional therapy ±CPAP; Hypopnea-mild→APAP/MAD/lifestyle.
- ⚠️ **HST (ApneaLink Air, Type-3) caveats:** no EEG staging → no REM-phenotype, AHI on recording-time may **underestimate**; central-vs-obstructive without manometry → label "suspected".

### Vendor- & test-type-agnostic data model (Nótt is NOT ResMed-only)
`mimir-sleep` normalizes **any vendor + any AASM test type (1/2/3/4)** into one canonical model. **EDF/EDF+ is the lingua franca** (most PSG/HSAT systems export it); ResMed `.mmrx` (zip→EDF) and any non-EDF vendor get an adapter that converts into the same canonical shape. Three layers:
1. **`SignalReader` trait** (per format): EDF/EDF+ (primary), ResMed `.mmrx`, + future Philips/Nox/Compumedics/Natus adapters → a common `RawStudy`.
2. **Canonical channel map** (config-driven alias table): vendor labels → canonical channels (`SaO2`/`Sat%`→SpO2, `Airflow`/`NasalPressure`→Flow, `Thor`/`Abdo`→Effort, `C3`/`C4`/`O1`→EEG, EOG, ChinEMG, LegEMG, ECG, Snore, BodyPosition, CPAP pressure/leak…) — so the engine never hard-codes a brand's labels.
3. **Test-type capability**: `test_type ∈ {1 attended-PSG, 2 unattended-PSG, 3 HSAT, 4 limited}` drives which features are valid. The engine computes the **superset** and marks each feature `available/valid`:
   - **Type 1/2** (have EEG) → real **sleep-time** AHI + hypnogram (N1/N2/N3/REM) + REM-AHI, arousal index, sleep efficiency, PLM (if leg EMG).
   - **Type 3** (HSAT, ApneaLink Air) → AHI on **recording-time** (⚠️ may underestimate), central/obstructive (if effort), positional, ODI/T90.
   - **Type 4** → oximetry-derived only (ODI/T90/SpO2).

Canonical `SleepStudy`: `{ source:{vendor,device_model,format,test_type}, recording, channels[{canonical,vendor_label,rate,unit,present}], hypnogram?, events[{type,start,dur,position?,stage?}], features{ahi, ahi_basis, ai, hi, central_pct, csr, odi, t90, …, rem_ahi?, sleep_efficiency?, arousal_index?, plm_index?, stage_pct?}, phenotype, quality, engine_version }`. FHIR: DiagnosticReport with **LOINC distinguishing PSG vs HSAT** + Device(vendor/model) + test-type coded.

## Alternatives considered

1. **OpenEMR-backed sleep record (rejected)** — user explicitly doesn't want it; ADR-012 says we don't run a full EHR. Smart-on-FHIR module on `mimir-fhir` instead.
2. **Eir owns FHIR storage (rejected)** — violates ADR-014; storage stays Mimir-family.
3. **Official ResMed API (preferred-if-available, deferred)** — none chosen now → scrape; keep as a future drop-in for the acquisition stage only.
4. **Store EDF as an opaque blob only, no FHIR mapping (rejected)** — loses queryability/clinical value. Do **both**: blob in MinIO + mapped FHIR resources.
5. **New Norse component for the scraper (rejected)** — use `bifrost-jobs` + a `mimir-sleep` submodule (family rule).

## Consequences

- **Positive:** Asgard owns the sleep record in FHIR R5, queryable + analysable, no OpenEMR dependency; acquisition is swappable (scrape → API later); governance built-in.
- **Negative / cost:** scraper is brittle + ToS-sensitive; PHI + Vault credential handling; EDF parsing + FHIR mapping effort; one new submodule; a headless browser in the job runtime.

## Follow-ups
- Execution detail: [eir-sleep-resmed-execution-plan.md](../strategy/eir-sleep-resmed-execution-plan.md)
- Confirm ResMed ToS/legal (gating P0).
- Add the sleep-study profile to the Asgard FHIR profile family (ADR-016).
