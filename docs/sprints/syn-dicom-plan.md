# `syn-dicom` — DICOM Ingestion Submodule

**Status:** Draft · **Created:** 2026-05-19 · **Owner:** TBD · **Target:** Sprint 53 — Sprint 56

> DICOM ingestion as a submodule of **Syn** (not a new Norse component, per
> [`feedback_no_new_norse_components`](../../docs/decisions/)). Lives at
> `Syn/services/dicom/` alongside `services/api`.

---

## 1. Identity

| Field | Value |
|---|---|
| Submodule | `syn-dicom` |
| Repo path | `Syn/services/dicom/` |
| Language | Rust 100% (Asgard Rust-first principle) |
| License | `AGPL-3.0-only OR LicenseRef-Commercial` |
| Initial version | `v0.1.0` |
| Service port | `8086` (reserved — verify with `lsof` before deploy) |
| AE Title | `ASGARD` |
| Tenants | `asgard_medical` (primary), `asgard_wellness`, `asgard_insurance` |

## 2. Crate Layout

```
Syn/services/dicom/
├── Cargo.toml                       # workspace root
├── README.md
├── Dockerfile
├── deploy/k8s/
└── crates/
    ├── syn-dicom-core/              # parse, decode, FHIR mapping
    ├── syn-dicom-anon/              # PS3.15 anonymization + Skuggi bridge
    ├── syn-dicom-net/               # DIMSE (C-STORE/FIND/MOVE) + DICOMweb
    ├── syn-dicom-api/               # axum HTTP service (bin)
    ├── syn-dicom-cli/               # offline tool (bin)
    └── syn-dicom-eval/              # benchmarks
```

## 3. Architecture (Data Flow)

```
┌─────────────────┐
│ PACS / Modality │  HOSxP / Trakcare / Siemens / GE
└──────┬──────────┘
       │ DIMSE C-STORE (TCP 11112)  or  DICOMweb STOW-RS (HTTPS)
       ▼
┌──────────────────────────────────────┐
│ syn-dicom-net  (AE Title: ASGARD)    │
└──────┬───────────────────────────────┘
       │ raw .dcm + metadata
       ▼
┌──────────────────────────────────────┐
│ syn-dicom-core    parse + decode      │
│  ├─ metadata → FHIR ImagingStudy      │
│  ├─ pixel → PNG (VLM-ready)           │
│  └─ SR → text chunks                  │
└──────┬───────────────────────────────┘
       │
       ├──► syn-dicom-anon ──► Skuggi (burned-in PHI OCR+inpaint)
       │                       │
       │                       └──► Tyr (PROV-AGENT audit)
       ▼
┌──────────────────────────────────────┐
│ Heimdall JWT-gated dispatch          │
└──────┬───────────────────────────────┘
       │
       ├──► Mimir (chunks + ImagingStudy index)
       ├──► Eir-radiology / -ophthalmology (VLM local: medgemma)
       └──► MariaDB (asgard_medical.imaging_studies)
```

## 4. Public API (port 8086, JWT-gated via Heimdall)

| Endpoint | Method | Purpose |
|---|---|---|
| `/dicom/ingest` | POST (multipart) | Upload one or more `.dcm` files |
| `/dicom/study/:uid` | GET | Metadata + FHIR `ImagingStudy` |
| `/dicom/study/:uid/frame/:n` | GET | PNG/JPEG (anonymized) |
| `/dicom/study/:uid/sr` | GET | DICOM SR → text |
| `/wado-rs/studies/...` | GET | DICOMweb-conformant retrieve |
| `/qido-rs/studies?...` | GET | DICOMweb-conformant query |
| `/dimse/peers` | GET | AE Title registry |
| `/healthz`, `/metrics` | GET | k8s probes + Prometheus |

`JWT_AUDIENCE=syn-dicom` (lowercase, per `asgard_jwt_auth_pattern`).

---

## 5. Sprint Breakdown

### Sprint α — Ingest MVP `v0.1.0` (2 weeks)
**Goal:** parse + convert + CLI working offline.

| # | Task | Type | Est | Owner |
|---|---|---|---|---|
| α-1 | Workspace skeleton + CI (clippy/test/audit) | infra | 0.5d | DevOps |
| α-2 | `syn-dicom-core`: parse single-frame `.dcm` (CR/CXR) | TDD | 2d | Backend |
| α-3 | Pixel decode → PNG (JPEG2000/RLE/raw) | TDD | 2d | Backend |
| α-4 | Metadata → FHIR `ImagingStudy` R4 (serde_json) | TDD | 1.5d | Backend |
| α-5 | PS3.15 Basic Profile anonymizer (tag-level) | TDD | 2d | Backend |
| α-6 | Thai charset handling (`ISO_IR 166`, `ISO 2022 IR 166`) | TDD | 1d | Backend |
| α-7 | `syn-dicom-cli`: `anon`, `convert`, `inspect` | TDD | 1d | Backend |
| α-8 | Synthetic fixtures generator (Python pydicom one-off) | tooling | 0.5d | QA |
| α-9 | Bench harness: 100 CXR parse < 1s/file (Mac mini) | bench | 0.5d | QA |

**Exit gate:**
- ✅ 80%+ test coverage on `syn-dicom-core`
- ✅ CLI anonymize passes DICOM PS3.15 Annex E sample set (8/8)
- ✅ Parse speed ≥ 100 files/s on Mac mini 64GB

**Risks:** low — `dicom-rs` is mature.

---

### Sprint β — Service + Skuggi Gate `v0.2.0` (2 weeks)
**Goal:** HTTP service in K8s, integrated with Heimdall + Skuggi + Tyr.

| # | Task | Type | Est | Dep |
|---|---|---|---|---|
| β-1 | `syn-dicom-api` axum skeleton + `/healthz` | infra | 0.5d | α |
| β-2 | Heimdall JWT middleware (`JWT_AUDIENCE=syn-dicom`) | TDD | 1d | — |
| β-3 | `POST /dicom/ingest` multipart + streaming | TDD | 2d | α-2 |
| β-4 | MariaDB schema: `imaging_studies`, `imaging_series` | schema | 1d | — |
| β-5 | Skuggi client: burned-in PHI request (image → masked PNG) | TDD | 2d | **Skuggi W2** ⚠️ |
| β-6 | Tyr PROV-AGENT audit hook | TDD | 1d | Tyr available |
| β-7 | DICOMweb WADO-RS read endpoint | TDD | 1.5d | β-3 |
| β-8 | K8s Helm chart + Bifrost route registration | infra | 1d | DevOps |
| β-9 | E2E test: ingest → anon → Mimir search | E2E | 1d | β-7 |

**Exit gate:**
- ✅ Ingest 10 studies end-to-end through Heimdall + Skuggi + Tyr
- ✅ Tyr audit log complete for every ingest (PROV.AGENT.signature)
- ✅ Deployed on OrbStack dev cluster

**Risks:**
- ⚠️ **Skuggi W2 (image-tier PHI) not yet shipped** — per `asgard_skuggi_state`. Stub with `image_phi_passthrough=true` + `docStatus=preliminary` if late.

---

### Sprint γ — PACS Network + SR `v0.3.0` (2 weeks)
**Goal:** receive from real PACS + parse Structured Report → Mimir.

| # | Task | Type | Est | Dep |
|---|---|---|---|---|
| γ-1 | DIMSE C-STORE SCP (AE: ASGARD) | TDD | 3d | α |
| γ-2 | C-FIND SCU + C-MOVE SCU (query PACS) | TDD | 2d | γ-1 |
| γ-3 | DICOM SR (TID 2000/3000) parser → text + observations | TDD | 2d | α-4 |
| γ-4 | SR text chunking → Mimir ingest (asgard_medical KB) | TDD | 1d | Mimir ready |
| γ-5 | Multi-frame series handler (CT/MR; preview only) | TDD | 1d | α-3 |
| γ-6 | DICOMweb STOW-RS server-side | TDD | 1.5d | β-3 |
| γ-7 | AE Title registry UI (Bifrost cron monitor pattern) | UI | 1d | Bifrost UI |
| γ-8 | Load test: 100 CXR studies/min sustained | bench | 0.5d | — |

**Exit gate:**
- ✅ C-STORE from Orthanc test PACS passes
- ✅ SR → Mimir + retrievable in `/search` UI
- ✅ Throughput ≥ 60 studies/min

**Risks:**
- DIMSE protocol is bug-prone; reserve **+30% time buffer**
- Real PACS conformance varies (HOSxP non-conformant) — keep tolerant parsing

---

### Sprint δ — Eir Integration + Productionize `v1.0.0` (2 weeks)
**Goal:** VLM hookup, multi-tenant, customer-ready.

| # | Task | Type | Est | Dep |
|---|---|---|---|---|
| δ-1 | Eir-radiology agent config (DB row, prompt + tool allowlist) | config | 0.5d | Eir registry |
| δ-2 | Tool: `dicom_study_view` (MCP via Hermodr) | TDD | 1d | Hermodr |
| δ-3 | VLM call: PNG → medgemma/gemma-4 (LOCAL only) | TDD | 1.5d | MLX VLM 8082/8083 |
| δ-4 | `DiagnosticReport` generation (FHIR R4) | TDD | 1d | α-4 |
| δ-5 | Eir-ophthalmology variant (fundus images, wellness tenant) | config | 0.5d | δ-1 |
| δ-6 | Multi-tenant routing (`tenant_id` → namespace/AE Title) | TDD | 1d | — |
| δ-7 | Heimdall oracle budget integration (cost guard) | TDD | 1d | budget cap |
| δ-8 | Compliance: PDPA + HIPAA audit checklist | docs | 1d | — |
| δ-9 | Smoke benchmark: end-to-end < 30s p95 (CXR → finding) | bench | 0.5d | — |
| δ-10 | Release notes + crates.io publish (`v1.0.0`) + tag | release | 0.5d | all |

**Exit gate:**
- ✅ Eir-radiology reads CXR for 10/10 synthetic cases
- ✅ p95 latency < 30s
- ✅ Compliance checklist signed off
- ✅ `v1.0.0` tagged + `scripts/deploy-all.sh` updated

---

## 6. Cross-Cutting (every sprint)

- **TDD:** red → green → refactor; no PR without test
- **Daily standup:** 9:00 AM (S1 pattern)
- **PR review:** 1 approver minimum; security-sensitive (anon, JWT) needs `/security-review`
- **ADRs:** every architectural decision → `Asgard/docs/decisions/`
- **Test data:** NO real patient DICOM in fixtures (per `syn_data_internal_only`). Use synthetic via pydicom + TCIA public sets.
- **Eir LLM:** LOCAL only (medgemma/gemma-4/typhoon) — cloud BANNED per `feedback_eir_agents_local_only`

## 7. Dependencies / Blockers

| Sprint | Hard blocker | Soft blocker |
|---|---|---|
| α | — | — |
| β | — | ⚠️ **Skuggi W2 (image PHI)** → stub if late |
| γ | Mimir asgard_medical KB ready | Bifrost cron UI shipped |
| δ | MLX VLM (medgemma) on 8082/8083 | Heimdall oracle budget shipped |

## 8. Decision Gates

- **After α:** continue? If parse perf < 50 files/s → optimize before β
- **After β:** Skuggi W2 status check; if not shipped → use stub + adjust timeline
- **After γ:** real PACS partner ready? If not → defer δ-1..5 and run research spike
- **After δ:** customer-ready? Beryl8/Prudential POC may be pulled in (separate sprint)

## 9. Sizing Summary

| Sprint | Engineer-days | Calendar | Tag |
|---|---|---|---|
| α | ~11d | 2w | v0.1.0 |
| β | ~11d | 2w | v0.2.0 |
| γ | ~11d | 2w | v0.3.0 |
| δ | ~9d | 2w | v1.0.0 |
| **Total** | **~42 engineer-days** | **8 weeks** | |

Approx. 1 backend engineer solo (S1 solo pattern), or 2 engineers parallel (~5 weeks).

## 10. Open Questions

1. Where do `.dcm` test fixtures live? (proposal: `services/dicom/tests/fixtures/synthetic/`, gitignore for real)
2. Should `syn-dicom-eval` ingest to `asgard_platform` (hash-only) for cross-engine metrics?
3. Does Eir-ophthalmology need its own VLM endpoint or share medgemma on 8082?
4. Does AE Title `ASGARD` need per-tenant variants (`ASGARD-MED`, `ASGARD-INS`)?

---

**Next actions:**
- [ ] Confirm sprint slot (Sprint 53 earliest, post-Guideline Lineage)
- [ ] Assign backend owner
- [ ] Spin up `Syn/services/dicom/` skeleton (this plan ships it)
- [ ] Create epic issues on `MegaWiz-Dev-Team/Syn` (one per sprint)
