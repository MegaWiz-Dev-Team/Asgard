# Asgard — System Context (start here)

> **One-pager · v0.1 · 2026-05-30.** The 30-second map of how the medical/insurance
> products fit together, plus the live list of cross-repo alignment decisions.
> Deep detail: per-repo `SPEC.md` (linked below). When this and a SPEC disagree, the SPEC wins.

## The four pieces

| Repo | Layer | One line | SPEC |
|---|---|---|---|
| **Asgard** | Platform | On-prem AI platform (LLM gateway, RAG, OCR, agents, ops). Not an EHR. | [SPEC](./SPEC.md) |
| **mimir-fhir** | Layer 1 (data) | Rust FHIR R5 type system + **terminology URIs**. Source of truth for codes. | [SPEC](../../Mimir/ro-ai-bridge/mimir-fhir/SPEC.md) |
| **asgard-iris** | Product | Claims **portal** — docs → extract → NHSO XML / สปสช EDI. Billing staff. | [SPEC](../../asgard-iris/docs/SPEC.md) |
| **asgard-underwriter** | Product | **Risk assessment** — 12-agent consensus → underwriting decision. Underwriter. | [SPEC](../../asgard-underwriter/docs/SPEC.md) |

> Iris ≠ Underwriter: different personas, different business process, no code dependency. ([[asgard_iris_vs_underwriter_split]])

## How they connect

```
                 ┌───────────────────────── Asgard platform services ─────────────────────────┐
                 │  Heimdall (LLM)   Syn (OCR)   Mimir (RAG + Neo4j glossary)   Bifrost  Skuggi │
                 └───────▲──────────────▲──────────────▲───────────────────────────────────────┘
                         │              │              │
   clinical documents    │   OCR text   │  ICD/abbrev  │              depends on (crate)
   (history, PE, notes,  │   + bbox     │  lookup      │        ┌───────────────────────┐
    orders, labs, …)     │              │              │        │  mimir-fhir (Layer 1)  │
        │                │              │              │        │  R5 datatypes + types  │
        ▼                │              │              │        │  terminology:: URIs ◀──┼── single source
   ┌─────────────────────┴──────────────┴──────────────┴────┐   └───────────▲───────────┘   of code systems
   │ asgard-iris  (claims portal)                           │               │
   │  extract → FHIR R5 → generate → NHSO XML / สปสช EDI    │───────────────┘ (extraction-service)
   └────────────────────────────────────────────────────────┘
   ┌────────────────────────────────────────────────────────┐
   │ asgard-underwriter  (risk assessment)                  │
   │  medical history → 12 agents → consensus risk decision │   (FHIR I/O planned → will use mimir-fhir)
   └────────────────────────────────────────────────────────┘

   Prototyping ground for the Iris flow: `Mimir/scripts/` + `Mimir/data/abb/`
   (extraction → FHIR R5 bundles → claim case + checklist + document-type registry)
```

## The document → outcome flow (medical/insurance)

```
1. gather      clinical documents for one patient + one case (Encounter)
2. normalize   document name → Asgard canonical type   (data/abb/registry/document_types.json)
3. extract     Syn OCR → entities → ICD-10-TM / TMT     (codes via mimir-fhir::terminology)
4. map         entities → FHIR R5 resources (Patient/Condition/Observation/MedicationRequest/…)
5a. claim      Iris: FHIR → NHSO XML + สปสช EDI 837-I    (gated by claim checklist: P0 must be complete)
5b. assess     Underwriter: history → 12-agent consensus → risk decision
```

## Open alignment points (track here)

| # | Decision | Owner | Status |
|---|---|---|---|
| **1** | **One canonical ICD-10-TM / TMT system URI.** Chosen: `https://terminology.fhir.moph.go.th/CodeSystem/icd-10-tm`. | mimir-fhir | ✅ **landed** in `mimir_fhir::terminology` (2026-05-30). **TODO consumers:** Iris migrate from `http://hl7.org/fhir/sid/icd-10-tm`; Python claim scripts import the const. |
| **2** | **FHIR resources don't exist yet** (mimir-fhir v0.0.1 = datatypes only). All resource-level FHIR work in Iris/Underwriter is gated on **Sprint 2**. Sprint 2 priority driven by the in-flight use cases: Patient, Encounter, Condition, Observation, MedicationRequest, Coverage, Claim, Composition, DocumentReference. | mimir-fhir | 🔜 Sprint 2 |
| **3** | **TH Core / MoPH-PC profile canonical URLs are provisional** (`https://fhir.moph.go.th/StructureDefinition/...` assumed). Confirm against the published Thai FHIR IG before any profile binding ships. Centralised in `terminology::profile`. | mimir-fhir | ⏳ pending IG |

## Decisions made (so we don't relitigate)

- **R5 canonical**, R4 only at adapter boundary (ADR-013). Never reimplement FHIR types — depend on `mimir-fhir`.
- **API endpoint detail is deliberately NOT specced yet** — contracts still drift (e.g. Syn `file_data`→`image_base64` fix, [[syn_extract_json_contract]]). Spec endpoints once contracts stabilise.
- On-prem, single-tenant per box. Tenants: `asgard_medical`, `asgard_insurance`, `asgard_platform`.
