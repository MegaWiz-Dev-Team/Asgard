# ADR-012: FHIR-Native Data Plane + Modular EHR Components (NOT Full EHR Replacement)

**Status:** Accepted (amended 2026-05-23 — see [Amendment 1](#amendment-1--2026-05-23-moph-pc1-conformance))
**Date:** 2026-05-23
**Deciders:** paripol@megawiz.co
**Scope:** Strategic positioning of Asgard relative to existing EHR systems (OpenEMR, HOSxP, Epic, Cerner). Defines what Asgard **is** and what Asgard **is not** in the EHR landscape. Locks the 3-layer architecture for clinical data flow and the build-vs-buy choice for the FHIR data plane.
**Related:** [ADR-006 FHIR canonical design](ADR-006-fhir-canonical-design.md), [ADR-013 FHIR R5 as canonical version](ADR-013-fhir-r5-canonical-version.md), [ADR-009 single-tenant Mac mini deployment](ADR-009-single-tenant-mac-mini-deployment.md), [ADR-010 agents as boundaries, skills as expertise](ADR-010-agents-as-boundaries-skills-as-expertise.md), [ADR-003 shared doc-pipeline crate](ADR-003-shared-doc-pipeline-crate.md), [MOPH-PC1 FHIR mapping](../architecture/moph_pc1_fhir_mapping.md)

## Amendment 1 — 2026-05-23 (MOPH-PC1 Conformance)

Audit of the [MOPH-PC1 Data Element Mapping](../architecture/moph_pc1_fhir_mapping.md) (same day as this ADR was accepted) revealed:

1. The spec targets FHIR **R5**, not R4 → locked in [ADR-013](ADR-013-fhir-r5-canonical-version.md). All wire formats and canonical store in this ADR are R5.
2. The spec requires 17 resources; ADR-006 had 15 → [ADR-006 Amendment 1](ADR-006-fhir-canonical-design.md#amendment-1--2026-05-23) added Location, Immunization, Specimen, ImagingStudy, Device.
3. Legacy MOPH 43-Files dataset (used by every Thai hospital) maps to ~60% of MOPH-PC1 elements directly → 43Files-to-FHIR adapter is added as a **Phase 1 deliverable** (D5 below).
4. The 78-row element mapping is canonicalized at [`docs/architecture/moph_pc1_fhir_mapping.md`](../architecture/moph_pc1_fhir_mapping.md) and is the ground truth for adapter implementers.

Phase 1 acceptance criteria (D5) now explicitly require MOPH-PC1 conformance for the 20-resource scope plus a working 43Files-to-FHIR adapter for the gold-value tables (`PERSON`, `SERVICE`, `ADMISSION`, `DIAGNOSIS_*`, `DRUG_*`, `PROCEDURE_*`, `NCDSCREEN`, `LABFU`).

## Context

Asgard currently integrates with existing hospital EHRs (OpenEMR via Eir-Gateway CryptoGen; HOSxP and others via Hermodr MCP adapters). Two pressures recently converged that prompted the question "should we build a new FHIR-native EHR to replace OpenEMR?":

1. **Clinical workflow gaps** identified during a 2026-05-23 review (see conversation history): Asgard covers OCR, decision support, triage, drug interactions, patient communication, audit. It does **not** cover CPOE, order sets, clinical pathways, real-time vital signs, lab HL7 v2, nursing-specific workflows (MAR, SBAR), DDx engine, OR/anesthesia, mental health agents, OB/GYN agents, SNOMED/CPT coding depth, antibiotic stewardship, consent management, AE reporting. Many of those gaps look like "things an EHR has."
2. **Thai MOH FHIR Thailand IG** (fhir.moph.go.th) makes FHIR-native architecture timely. ADR-006 already locked the internal FHIR R4 type system for `asgard-doc-pipeline-core`.

Three options were on the table:

- **A. Build a full Asgard EHR (FHIR-native, replaces OpenEMR/HOSxP for our customers)**
- **B. Build a FHIR-native data plane + ship modular clinical components; existing hospital EHR stays as front-end**
- **C. Status quo (OpenEMR integration + Hermodr MCP adapters; AI sits on top of legacy EHR)**

This ADR closes that question and locks Option B as the multi-year direction.

## Decision

**Asgard will NOT build a full EHR.** Asgard will build a FHIR-native data plane in Rust and ship modular clinical components that plug into existing hospital EHRs via Smart-on-FHIR + Hermodr MCP. Greenfield clinics (small/specialty practices without an installed EHR) may use Asgard's modular components as a primary EHR-Lite, but the strategic target is **coexistence**, not replacement.

### D1. Three-layer architecture (locked)

```
+---------------------------------------------------------------+
|  Layer 3: EHR Front-end (NOT built by Asgard)                 |
|  HOSxP / OpenEMR / Epic / Cerner / Trakcare / hospital's EHR  |
|                  ^                                            |
|                  | Smart-on-FHIR launch + Hermodr MCP         |
|                  v                                            |
+---------------------------------------------------------------+
|  Layer 2: Asgard Clinical Modules (FHIR-native, Rust)         |
|  - eir-ddx (differential diagnosis)                           |
|  - order-sets (FHIR PlanDefinition + ActivityDefinition)      |
|  - mar (MedicationAdministration)                             |
|  - sbar-handoff, or-checklist, acls-timer                     |
|  - care-pathway executor (FHIR CPG-IG)                        |
+---------------------------------------------------------------+
|  Layer 1: Asgard FHIR Data Plane (Rust, `mimir-fhir`)         |
|  - FHIR R4 store: Patient, Encounter, Observation,            |
|    MedicationRequest, Condition, DiagnosticReport,            |
|    DocumentReference, Coverage, Claim, Practitioner, ...      |
|  - Bidirectional sync OpenEMR <-> FHIR (canonical = FHIR)     |
|  - FHIR Thailand profile compliance                           |
|  - Audit + provenance via Tyr (per ADR-002)                   |
+---------------------------------------------------------------+
```

- Layer 3 is the hospital's existing system. Asgard does not own this layer.
- Layer 2 is what makes Asgard differentiated. Each module is a Smart-on-FHIR app launchable from the hospital's EHR + an MCP tool callable by Eir agents.
- Layer 1 is the canonical store. ADR-006 already locked the type system; this ADR locks that there **is** a canonical FHIR store called `mimir-fhir`.

### D2. `mimir-fhir` Rust submodule (new component, naming per [feedback_no_new_norse_components])

A new submodule of Mimir, named `mimir-fhir`, holds:

- FHIR **R5** resource types (designed in ADR-006, version locked in ADR-013)
- A minimal FHIR REST surface (`/fhir/r5/{ResourceType}/...`) — read-first, write-where-needed
- R4↔R5 translation adapter per ADR-013 D2 (every R4-emitting EHR routes through this)
- Bidirectional adapters: OpenEMR ↔ FHIR, HL7 v2 → FHIR (for lab), HOSxP → FHIR via 43Files (later)
- **43Files-to-FHIR adapter** for legacy MOPH dataset (gold-value tables: `PERSON`, `SERVICE`, `ADMISSION`, `DIAGNOSIS_*`, `DRUG_*`, `PROCEDURE_*`, `NCDSCREEN`, `LABFU`)
- TH Core + MoPH-PC profile validators (tightest-binding-wins per [mapping doc](../architecture/moph_pc1_fhir_mapping.md))
- MOPH-PC1 78-element conformance test corpus

Naming convention follows the established Mimir family ([[feedback_no_new_norse_components]]): `mimir`, `mimir-well`, `mimir-curator`, `mimir-fhir`.

### D3. Build vs Buy for the FHIR layer

The FHIR layer is **built in Rust on top of `fhir-rs` style crates from crates.io**, not adopted from HAPI FHIR / Medplum / Aidbox.

| Option | License | Language | Verdict |
|---|---|---|---|
| HAPI FHIR | Apache 2.0 | Java | Reject: violates [[asgard_rust_first_principle]]; JVM in single-Mac-mini deployment unacceptable. |
| Medplum | Apache 2.0 | TypeScript | Reject: Node.js runtime in core; cloud-first design fights single-tenant Mac mini ([[ADR-009]]); Apache 2.0 in core dilutes AGPL+Commercial moat ([[feedback_asgard_license]]). |
| Aidbox | Commercial | Clojure | Reject: proprietary dependency in core directly contradicts the open-core strategy. |
| Build in Rust on `fhir-rs` crates | crates.io permissive + Asgard AGPL/Commercial wrapper | Rust | **Chosen.** Aligns with Rust-first, single-binary Mac mini deploy, and ADR-006 type system. |

Resource coverage is **bounded to what we use**, not full FHIR R4. ADR-006 locks 15 resources (Patient, Encounter, Observation, Condition, MedicationRequest, MedicationStatement, Procedure, DiagnosticReport, AllergyIntolerance, DocumentReference, Coverage, Claim, ClaimResponse, Practitioner, Organization). Additional resources are added only when a module needs them.

### D4. Hospital coexistence is the default; EHR-Lite is a side effect

The strategic target is **large/mid hospitals keeping HOSxP/OpenEMR** with Asgard modules launching from inside their EHR via Smart-on-FHIR. This is where the moat (Living Clinical Evidence + on-prem AI) compounds.

A **secondary, opportunistic** target: small clinics or specialty practices with no installed EHR can adopt Asgard modules as a "Asgard EHR-Lite" (scheduling + encounter + notes + Rx). This is **not** a product line we invest in to compete with HOSxP/Epic — it is a side effect of having the modules built. If a customer wants more, refer them to a real EHR vendor.

Explicit non-goals (we will **not** build):

- Hospital billing / insurance claim adjudication (use Coverage/Claim FHIR resources for read; do not own the claim lifecycle)
- DRG grouping
- Inventory / pharmacy stock management
- Hospital scheduling beyond simple appointment slots
- Bed management / ADT messaging beyond what FHIR Encounter requires
- Radiology PACS / DICOM archive (Syn DICOM is a separate initiative — image **interpretation** support, not archive)

### D5. Roadmap phases (sprint placement TBD; gated by S1 Go/No-Go 2026-06-12)

**Phase 1 — FHIR Data Plane Foundation (`mimir-fhir` v0)**
- `mimir-fhir` Rust submodule scaffolding
- ADR-006 type system implemented in **R5** ([ADR-013](ADR-013-fhir-r5-canonical-version.md)), **20-resource scope** (ADR-006 Amendment 1), `External*` newtypes
- Read-only FHIR R5 REST endpoint for Patient + Encounter + Observation
- R4-emit content negotiation path (per ADR-013 D2) — verify R4 round-trip against a HAPI sandbox
- Bidirectional OpenEMR ↔ FHIR adapter (Patient + Encounter first)
- **43Files-to-FHIR adapter** covering the gold-value tables (`PERSON`, `SERVICE`, `ADMISSION`, `DIAGNOSIS_*`, `DRUG_*`, `PROCEDURE_*`, `NCDSCREEN`, `LABFU`) — proven against one HOSxP test database
- **MOPH-PC1 conformance suite** — 78-element test corpus from [mapping doc](../architecture/moph_pc1_fhir_mapping.md) round-trips green
- TH Core + MoPH-PC profile validation (tightest-binding-wins)
- Smart-on-FHIR app-launch from OpenEMR proven

**Phase 2 — First Smart-on-FHIR Module: `eir-ddx`**
- Differential diagnosis Smart-on-FHIR app launchable from OpenEMR
- Consumes FHIR Observation + Condition; returns ranked DDx
- Uses existing Eir specialty agents + PrimeKG (no new infra)
- Pilot with Beryl8 / one greenfield clinic

**Phase 3 — High-Value Clinical Modules**
- Order Sets (FHIR PlanDefinition + ActivityDefinition execution engine)
- MAR (FHIR MedicationAdministration)
- Care Pathway executor (FHIR CPG-IG; pairs with Mimir Guideline Lineage from Sprint 55)
- Lab HL7 v2 -> FHIR ingest

**Phase 4 — Nursing-first surface**
- SBAR handoff generator
- Nursing assessment templates (Braden, Morse, pain scale)
- Vital signs FHIR Observation stream + early warning score (NEWS/MEWS)

**Phase 5 — Optional EHR-Lite for greenfield clinics**
- Scheduling, encounter, notes, Rx as a packaged front-end on Layer 2 modules
- Not sold separately; only when a small-clinic customer asks
- Hard-cap scope: under 10 doctors, no billing, no inventory

Each phase is sized 1-2 sprints; full sequence spans 12-18 months and runs **after** the current Insurance Launch (S52-54) + Living Evidence (S55-58) sequences, not in parallel.

## Why this and not Option A or C

**Why not A (build full EHR):**

- Scope is multi-decade: Epic took 40+ years, HOSxP 20+. Megawiz cash burn cannot fund that.
- Regulatory burden (Thai FDA medical device class B/C, ISO 27799, HL7 certification) consumes engineering capacity that should go to AI/Living Evidence.
- Sales cycle 18-24 months for EHR vs 3-6 months for AI add-on. Cash flow incompatible with current Megawiz size.
- Hospitals do not rip-and-replace EHR. Going head-to-head with HOSxP at the EHR layer wastes the moat.
- Asgard moat is **Living Clinical Evidence + on-prem AI**, not "yet another EHR." Building EHR dilutes the moat.
- We already have working OpenEMR integration + Hermodr MCP — that capital should be amortized, not abandoned.

**Why not C (status quo):**

- Without a FHIR canonical, every EHR integration is bespoke. N hospital EHRs * M Asgard modules = N*M adapter pairs. With FHIR canonical, it is N + M.
- Hermodr MCP tools currently lack a stable FHIR-shaped contract; each tool reinvents schemas. ADR-006 fixes this for types; this ADR fixes it for the wire surface too.
- FHIR Thailand IG (MOH push) means hospital RFPs will start requiring FHIR conformance within 1-2 years. Asgard needs to be FHIR-native before then.
- Modules like CPOE, MAR, DDx do not fit cleanly as "tools on top of OpenEMR" — they need their own resource model. FHIR is that model.

## Consequences

**Positive:**

- Closes the architectural debt of bespoke per-EHR adapters; collapses to FHIR canonical + per-EHR adapter.
- Unlocks Smart-on-FHIR app distribution model — Asgard modules launchable from any FHIR-compliant EHR (Epic, Cerner included in the future).
- Aligns with MOH FHIR Thailand push; positions Asgard as a compliant vendor in coming hospital RFPs.
- Each module shipped (eir-ddx, MAR, order-sets, ...) is a saleable SKU, not a feature buried in a monolith.
- Preserves the AGPL+Commercial moat: core Layer 1+2 is Asgard IP under our license; we do not vendor Apache 2.0 / Java / TypeScript dependencies into core.
- Module-level pricing fits per-Mac-mini commercial model.

**Negative:**

- Building FHIR plumbing in Rust is more work than adopting HAPI FHIR or Medplum. 6-12 month investment for Layer 1 before first Layer 2 module ships.
- We must maintain FHIR type system as the standard evolves (R4 -> R4B -> R5). Manageable because resource scope is bounded.
- Hospital sales conversations now require explaining "we are not an EHR" repeatedly. Sales narrative discipline needed.
- Greenfield-clinic EHR-Lite path (Phase 5) creates a temptation to expand scope. We must hold the line at "no billing, no inventory."

**Neutral / TBD:**

- `mimir-fhir` exact crate boundary inside the Mimir workspace — to be designed alongside ADR-003 conventions.
- Whether FHIR REST endpoint is read-only at first or supports write from day 1 — defer to Phase 1 detail design.
- Lab HL7 v2 receiver: build in Rust or wrap a small adapter (e.g., Mirth)? — defer to Phase 3 detail design.

## What we explicitly do NOT do

| Tempting feature | Reason rejected |
|---|---|
| Replace OpenEMR / HOSxP for existing hospital customers | Sales cycle + scope; moat is AI, not EHR |
| Adopt HAPI FHIR / Medplum / Aidbox | Language + license + deployment-shape mismatch (see D3) |
| Implement all 145 FHIR R4 resources | Resource scope bounded to ADR-006 list + add-as-needed |
| Build hospital billing or DRG grouping | Out of scope; refer customers to billing vendors |
| Compete with HOSxP at hospital RFPs | Coexist instead; sell modules into HOSxP-shaped hospitals |
| Build a separate FHIR server product (`asgard-fhir-server` SKU) | Sold only as the data plane under modules; not a standalone product |

## Open questions

1. Should `mimir-fhir` be a sibling submodule (peer to `mimir-well`, `mimir-curator`) or a sub-submodule under `mimir-well` (since both are about the canonical knowledge layer)?
2. FHIR write surface for Phase 1: read-only with adapter-driven sync, or accept FHIR PUT/POST from day 1?
3. Smart-on-FHIR launch UX inside HOSxP specifically — HOSxP does not have a native Smart-on-FHIR launcher; do we build a HOSxP plugin or a separate launcher app?
4. Phase 5 EHR-Lite: does it get its own tenant (`asgard_clinic`) or live under `asgard_medical`?

## References

- ADR-006: FHIR canonical type system (implementation companion to this ADR; amended 2026-05-23)
- ADR-013: FHIR R5 as canonical version (version lock for `mimir-fhir`)
- ADR-009: single-tenant Mac mini deployment (shape constraint on FHIR layer)
- ADR-010: agents as boundaries, skills as expertise (Layer 2 modules follow this pattern)
- ADR-003: shared doc-pipeline crate (where FHIR types live)
- [`docs/architecture/moph_pc1_fhir_mapping.md`](../architecture/moph_pc1_fhir_mapping.md) — canonical 78-element MOPH-PC1 mapping
- HL7 FHIR R5 - http://hl7.org/fhir/R5/
- HL7 FHIR R4 (for adapter boundary) - http://hl7.org/fhir/R4/
- FHIR Thailand IG - https://fhir.moph.go.th
- Smart-on-FHIR - https://docs.smarthealthit.org/
- `fhir-rs` family on crates.io
- MOPH 43-Files dataset standard — Thai Ministry of Public Health