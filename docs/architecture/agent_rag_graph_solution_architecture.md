# Asgard Solution Architecture — Agent / MCP / RAG / Graph / PageIndex / RefGraph

**Status:** Draft v1
**Date:** 2026-05-17
**Scope:** Knowledge & reasoning stack across Asgard Medical + Asgard Insurance deployments
**Audience:** internal engineering + technical sales

## 1. Problem

Asgard must answer questions and make decisions over heterogeneous documents (scanned charts, policy PDFs, medical certificates, claim forms) using a mix of:

- **Public medical knowledge** (PrimeKG — 129K nodes, 8.1M relations, already imported)
- **Customer-specific document corpora** (per Mac mini: hospital records / insurance products)
- **Standardized coding systems** (ICD-10-TM, TMT, TPC, LOINC, SNOMED CT)
- **Real-time reasoning** from medical/insurance specialists (Eir variants)

The challenge: a single retrieval pattern (chunked vector search) is **insufficient**. We need multiple knowledge representations and retrieval granularities, orchestrated by domain-aware agents — running locally on a single Mac mini per customer with no cross-customer leakage.

## 2. Component Map

| Component | Layer | Role | Status |
|---|---|---|---|
| **Syn** | Input | OCR — Thai handwriting champion typhoon-1.5-3b | shipped |
| **Skuggi** | Input | PII gate — text Tier 1 shipped; image tier W2/W3 pending | partial |
| **Mimir** | Indexing + Retrieval | RAG service: BGE-M3 embeddings + Qdrant + Neo4j orchestration | shipped (Sprint 48 active) |
| **Neo4j** | Graph storage | Hosts PrimeKG + RefGraph + SAME_AS links | running in K8s |
| **Qdrant** | Vector storage | Chunk embeddings + (planned) page-level embeddings | running in K8s |
| **RefGraph** | Graph derivation | Document → entity extraction → consolidated graph (per deployment) | S1 active (May 19-28 + Jun 2-11) |
| **PageIndex** | Document navigation | Hierarchical page-level index for long docs (NEW pattern, not yet built) | proposed |
| **Heimdall** | LLM gateway | Local MLX (gemma-4-26b) + cloud passthrough via Skuggi | shipped |
| **Bifrost** | Orchestrator | Routes requests to Eir agent variants; enforces tenant boundary | shipped |
| **Hermodr** | MCP catalog | Tool registry + invocation gateway | shipped |
| **Eir + variants** | Agent | Domain reasoning — **19 agents designed** (13 specialists + 6 allied health) + eir-router; **5/19 deployed** as Sprint 38 PoC. See [Eir_Agents_Architecture.md](../../../Eir/docs/Eir_Agents_Architecture.md) | partial (5/19 LIVE) |
| **Tyr** | Audit/SIEM | Per-deployment audit; Wazuh stub during scale-down | scaled-down |
| **MariaDB/Postgres** | Tabular storage | Cases, audit_events, icd10_codes, chat_sessions | running |

## 2.1 Per-Tenant Component Allocation

Per [ADR-009](../decisions/ADR-009-single-tenant-mac-mini-deployment.md), each Mac mini hosts ONE tenant. All infrastructure components are installed on every box; **agent set + knowledge data + tool catalog differ per tenant**.

### Shared infrastructure (identical on every box)

| Component | Per-tenant variation |
|---|---|
| Bifrost | `JWT_AUDIENCE` config per tenant |
| Heimdall | local MLX; model availability per tenant |
| Hermodr | tool filter by tenant |
| Skuggi | global rules |
| Tyr | LocalDbSink per box |
| Mimir | collection naming `{tenant}_{collection}` |
| Syn | global model |
| Yggdrasil | tenant claim issuance |
| MariaDB / Qdrant / Neo4j | schemas/collections per tenant |

### `asgard_medical` box (Mega Care + future hospitals)

**Agents** (in `agent_configs` table, all rows with `tenant_id='asgard_medical'`):
- **19 Eir agents** = 13 medical specialists + 6 allied health (per [Eir_Agents_Architecture.md](../../../Eir/docs/Eir_Agents_Architecture.md))
- eir-router (Bifrost routing logic)
- **All agents use LOCAL LLM only** — gemma-4-26b champion, medgemma-27b-text for pediatrics/psychiatry, quantized Q4/Q8 for low-latency emergency/nursing/ent. **NO gemini, NO cloud LLM** (see [feedback_eir_agents_local_only memory](memory))
- **Eir Gateway (OpenEMR)** — patient/encounter/medication system of record (FHIR R4)
- Sprint 38 PoC currently has 5/19 deployed; PoC names `eir-cardio` and `eir-sleep` are NOT in target 19 (absorbed into `eir-internal-medicine`); 14 remaining queued for Sprint 43+

**Knowledge data populated:**
- PrimeKG — full 129K nodes / 8.1M relations in Neo4j ✅ already loaded
- ICD-10-TM + TMT + TPC in MariaDB ✅ ICD-10-TM anamai 2010 done
- Clinical guidelines + hospital SOPs + PubMed abstracts subset in Qdrant vector
- PageIndex on: medical chart bundles, hospital protocols, drug formulary, reference manuals

**RefGraph schema (per-deployment, medical-flavored):**
```
(Patient) -[:DIAGNOSED_WITH {date, confidence, source_doc}]-> (Condition) -[:SAME_AS]-> (PrimeKG:Disease)
(Patient) -[:PRESCRIBED {date, source_doc}]-> (Medication) -[:SAME_AS]-> (PrimeKG:Drug)
(Patient) -[:UNDERWENT {date, source_doc}]-> (Procedure)
(Patient) -[:HAS_VISIT]-> (Encounter) -[:CAPTURED_IN]-> (Document)
```

**Hermodr tool catalog (medical scope, ~35 tools):**
- `primekg.*` (6) — drug/disease knowledge
- `refgraph.*` (5) — patient entity graph
- `pageindex.*` (4) — chart navigation
- `mimir.search_chunks`
- `icd10/tmt/tpc.lookup`
- `clinical_calculator.*` (CHADS2/MELD/eGFR/PHQ-9/GAD-7/Wells/NEXUS/GCS/ASA/Mallampati)
- `dosage_calculator.*` (pediatric-aware)
- `drug_interaction_check.*`, `drug_food_interaction`
- `formulary_lookup`, `patient_education_lookup`, `antibiogram_lookup`, `lab_reference_range`, `community_resource_lookup`
- `pubmed_search`
- `read_fhir.*` (Eir Gateway)
- `syn.extract` (medical chart OCR)
- `audit.query`

**Workflows (per Eir_Agents_Architecture.md §4):**
- Outpatient / Surgical / Emergency / Pediatric — full 4 flows

### `asgard_insurance` box (Insurer A, Insurer B, Insurer C)

**Agents** (in `agent_configs` table, all rows with `tenant_id='asgard_insurance'`):
- **Underwriter consensus agents** (NOT the 19 Eir):
  - `underwriter-risk-assessor`
  - `underwriter-medical-analyzer`
  - `underwriter-fraud-detector`
  - `underwriter-decision-maker`
- **Restricted 3-agent Eir subset (READ-ONLY)** for clinical interpretation of applicant history:
  - `eir-internal-medicine` (read-only tools)
  - `eir-medtech` (read-only labs)
  - `eir-pharmacy` (read-only drug knowledge for risk)
  - These use the same templates as medical but with tool allowlist restricted to read-only knowledge tools — no FHIR write, no patient education tools, no clinical actions
- **All agents LOCAL LLM only** — same rule applies; no gemini
- **No Eir Gateway** — insurance is not an EHR system of record

**Knowledge data populated:**
- PrimeKG — same loaded (drug/disease knowledge for underwriting medical history analysis)
- ICD-10-TM + TMT in MariaDB — TPC NOT loaded (procedures = hospital concern)
- Insurance product catalogs (Insurer A/Insurer B/Insurer C) in tabular + vector
- Underwriting manuals + exclusion catalogs in vector
- PageIndex on: policy PDFs (50-200 page), claim documents, medical certificates submitted

**RefGraph schema (per-deployment, insurance-flavored):**
```
(Applicant) -[:DIAGNOSED_WITH]-> (Condition) -[:SAME_AS]-> (PrimeKG:Disease)
(Applicant) -[:PRESCRIBED]-> (Medication) -[:SAME_AS]-> (PrimeKG:Drug)
(Applicant) -[:FILED_CLAIM]-> (Claim) -[:AGAINST_PRODUCT]-> (Product)
(Product) -[:OFFERED_BY]-> (Insurer)
(Product) -[:COVERS]-> (Condition)
(Product) -[:EXCLUDES]-> (Condition)
(Document) -[:ABOUT_APPLICANT]-> (Applicant)
```

**Hermodr tool catalog (insurance scope, ~30 tools — fewer than medical):**
- `underwriter.*` (9) — case workflow + risk + fraud + analytics + HITL
- `primekg.*` (6) — READ-ONLY clinical knowledge
- `refgraph.*` (5) — applicant + product entity graph
- `pageindex.*` (4) — policy/claim doc navigation
- `mimir.search_chunks`
- `icd10/tmt.lookup` — TPC not loaded
- `clinical_calculator.*` (restricted to risk-relevant: eGFR, MELD, CHADS2 — not the full medical set)
- `drug_interaction_check` (for applicant medication risk review)
- `syn.extract` (claim doc + medical certificate OCR)
- `audit.query`

**Workflows:**
- New case: Intake → OCR → Skuggi PII → Risk assessor → Medical analyzer → Fraud detector → Decision maker → HITL queue (low-conf) → PDF
- Renewal: Pull case → re-assess → decision
- Product comparison: across loaded insurers' catalogs

### Components NOT installed on either tenant currently

- Sága (STT, third-party Laminar) — future, both
- Bragi (TTS) — future, both
- Muninn (auto-fix) / Huginn (scanner) — private commercial; separate cybersecurity track
- Odin — public, separate track

## 3. Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  USER (clinician / underwriter / portal bridge)                │
└──────────────────────────────┬──────────────────────────────────┘
                               │ JWT (Yggdrasil RS256)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  BIFROST  — orchestrator + tenant context + auth                │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  EIR-ROUTER  (decides which specialty: cardio/sleep/ent/peds)   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
   ┌─────────────────────┐         ┌──────────────────────────┐
   │ EIR specialty agent │         │  HEIMDALL (LLM gateway)  │
   │ - reasoning loop    │◀───────▶│  - local MLX (default)   │
   │ - tool calling      │         │  - cloud (via Skuggi)    │
   └──────────┬──────────┘         └──────────────────────────┘
              │ MCP tool invocation
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  HERMODR  — MCP tool catalog                                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐  │
│  │ primekg.*    │ │ refgraph.*   │ │ pageindex.*           │  │
│  │ search/      │ │ entity_at/   │ │ pages_with_term/     │  │
│  │ neighbors/   │ │ neighbors/   │ │ page_chunks/         │  │
│  │ drug_inter   │ │ same_as      │ │ table_of_contents    │  │
│  └──────┬───────┘ └──────┬───────┘ └──────────┬───────────┘  │
│         │                │                     │              │
│  ┌──────▼───────┐ ┌──────▼─────────────────────▼───────────┐  │
│  │ mimir.search │ │ underwriter.*  /  syn.*  /  …          │  │
│  └──────┬───────┘ └────────────────────────────────────────┘  │
└─────────┼────────────────────────────────────────────────────────┘
          │
   ┌──────┴──────┬──────────┬─────────────┬──────────────┐
   ▼             ▼          ▼             ▼              ▼
┌──────┐   ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌────────┐
│Qdrant│   │  Neo4j   │ │ Neo4j    │ │  MariaDB     │ │  S3/   │
│chunks│   │ PrimeKG  │ │ RefGraph │ │  icd10_codes │ │ MinIO  │
│+pages│   │ (public) │ │ (per-dep)│ │  cases,…     │ │ docs   │
└──────┘   └──────────┘ └──────────┘ └──────────────┘ └────────┘
      ▲           ▲           ▲              ▲           ▲
      └───────────┴───────────┼──────────────┴───────────┘
                              │
              ┌───────────────┴────────────────┐
              │  INGESTION PIPELINE            │
              │  (asgard-doc-pipeline crate)   │
              │                                │
              │  raw file                      │
              │   ↓ Syn (OCR)                  │
              │   ↓ Skuggi (PII gate)          │
              │   ↓ Chunking (recursive+Thai)  │
              │   ↓ BGE-M3 embed               │
              │   ↓ Qdrant upsert              │
              │   ↓ RefGraph entity extract    │
              │   ↓ Neo4j RefGraph upsert      │
              │   ↓ PageIndex hierarchical idx │
              │   ↓ SAME_AS link → PrimeKG     │
              │   ↓ Tyr audit event            │
              └────────────────────────────────┘
```

## 4. Knowledge Representations — Comparison

Asgard maintains **4 complementary indexes**, each optimized for different query patterns:

| Index | Storage | Granularity | Strength | Weakness | Update cost |
|---|---|---|---|---|---|
| **Vector chunks** | Qdrant | ~500-800 tokens | Semantic similarity, fuzzy match | No structure awareness, no exact lookup | Low (embed + upsert) |
| **PrimeKG** | Neo4j (shared) | Entity (drug/disease/...) | Public medical knowledge, drug interactions, mechanism reasoning | Static, no customer data | One-time + monthly refresh |
| **RefGraph** | Neo4j (per-deployment) | Entity + reference | Customer-specific entities, cross-doc resolution | Quality depends on extractor | Per-ingestion update |
| **PageIndex** | Qdrant + DB | Page (PDF page) → chunks | Long-doc navigation, "show me page where X" | Storage 2× chunks | Same as chunks |
| **SAME_AS** | Neo4j edges | Entity ↔ Entity | Bridge customer entities to public KG | Confidence depends on linker | Per-RefGraph build |

### Query → Index routing

| Query pattern | Primary index | Secondary | Example |
|---|---|---|---|
| "ยานี้รักษาอะไรได้" | PrimeKG | — | drug → indication relations |
| "ผู้ป่วยรายนี้มีโรคอะไรบ้าง" | RefGraph | Tabular DB | case_id → diagnoses |
| "ในกรมธรรม์ Insurer A เขียนอย่างไรเรื่อง pre-existing" | Vector + PageIndex | — | semantic search → drill to page |
| "ICD-10 ของเบาหวานชนิด 2 คืออะไร" | Tabular (icd10_codes) | — | exact lookup |
| "เปรียบเทียบยา Atorvastatin กับ Rosuvastatin" | PrimeKG | Vector (clinical guidelines) | drug nodes + their indication neighbors |
| "ระบุยาที่ห้ามใช้ในผู้ป่วยตั้งครรภ์" | PrimeKG (`contraindication`) | RefGraph (cross-reference patient history) | graph traversal |
| "ผู้สมัครรายนี้มี risk factor อะไรบ้าง" | Tabular + RefGraph + PrimeKG | Vector (medical notes) | multi-source fusion |
| "หน้าไหนของ chart พูดถึง CPAP titration" | PageIndex | Vector (chunks within page) | page-level → chunk-level drill |

## 5. PageIndex — Detailed Design

PageIndex is a **new pattern** Asgard should adopt for long-document corpora (policy PDFs, medical chart bundles, manuals).

### Why PageIndex (vs flat chunk vector search alone)?

Insurance policies are 50-200 page PDFs. A flat chunk vector search will:
- Return chunks from random pages
- Lose document hierarchy (sections, chapters)
- Make "navigate to the part that says X" awkward
- Fragment table-of-contents semantics

PageIndex addresses these by maintaining a **hierarchical index**:

```
Document
├── Section (Chapter 3: Pre-existing Conditions)
│   ├── Page 47
│   │   ├── Chunk 47.1 (paragraph A)
│   │   ├── Chunk 47.2 (paragraph B)
│   │   └── Chunk 47.3 (table)
│   ├── Page 48
│   └── Page 49
└── Section (Chapter 4: Exclusions)
```

### Schema

**Qdrant collections:**
- `chunks-{tenant}` — chunk-level embeddings (existing)
- `pages-{tenant}` — page-level embeddings (NEW): page = aggregate (mean or summary) of chunk embeddings on that page
- `sections-{tenant}` — section-level embeddings (NEW, optional): for very-long docs

**Metadata per page (in Qdrant + sidecar in DB):**
```json
{
  "doc_id": "policy_insurer_a_term_v2",
  "page_num": 47,
  "section": "Pre-existing Conditions",
  "section_id": "ch3",
  "page_summary": "Defines pre-existing condition exclusions, waiver options, and look-back period of 24 months...",
  "chunk_ids": ["c_47_1", "c_47_2", "c_47_3"],
  "outline_level": 2,
  "language": "th"
}
```

### Retrieval modes

1. **Direct chunk** (existing) — query → top-K chunks
2. **Page-first** (NEW) — query → top-K pages → for each, list chunks (or summarize)
3. **Section-first** (NEW) — query → top-K sections → drill into pages → drill into chunks
4. **Outline (ToC)** (NEW) — return document outline with relevance scores per section/page (no chunk content)

### Hermodr MCP tools

```
pageindex.search_pages(query, doc_id?, limit) → [{doc_id, page_num, score, summary}]
pageindex.page_chunks(doc_id, page_num) → [chunks]
pageindex.toc(doc_id) → document outline tree
pageindex.section_chunks(doc_id, section_id) → [chunks]
```

### Effort estimate (new workstream)

| Task | Effort |
|---|---|
| Page-level embedding generation (mean or summary) | 1d |
| Qdrant `pages-{tenant}` collection + upsert pipeline | 1d |
| Section detection (TOC parsing, heading extraction) | 2-3d |
| 4 Hermodr MCP tools | 2d |
| Eval set + benchmark | 1-2d |
| **Total** | **~1.5 weeks** |

→ **Recommended placement:** Underwriter v3 Phase C (after chunking remediation lands; PageIndex builds on improved chunking)

## 6. RefGraph — Detailed Design

RefGraph is a **per-deployment, document-derived knowledge graph** that complements PrimeKG.

### Difference from PrimeKG

| | PrimeKG | RefGraph |
|---|---|---|
| Source | Harvard biomedical KGs (20+ sources) | Customer's ingested documents |
| Scope | Public medical knowledge | Customer-specific entities + relationships |
| Update | One-time + Harvard releases | Continuous (every doc ingest) |
| Persistence | Shared across deployments (same data on every box) | Unique per Mac mini |
| Examples | "Metformin → indication → T2DM" | "Applicant APP-1234 → diagnosed with → T2DM" |

### Pipeline (already in S1 Sprint)

```
Document chunks
    ↓
Entity extractor (refgraph-rs crate)
    ↓
Entity normalization (NER, ICD-10 lookup, TMT lookup)
    ↓
Relation extraction (chunk-local relations)
    ↓
Cross-chunk entity resolution (same entity mentioned in different places)
    ↓
RefGraph nodes + edges to Neo4j
    ↓
SAME_AS linking to PrimeKG (entity ID match or name match)
```

### Schema (S1-validated)

**Nodes:**
```
(:RefGraph:Person {id, name, citizen_id_hash, ...})
(:RefGraph:Condition {id, icd10_code, name, ...})
(:RefGraph:Medication {id, tmt_code, name, dose, ...})
(:RefGraph:Procedure {id, tpc_code, name, ...})
(:RefGraph:Document {id, source, page, ...})
(:RefGraph:Insurer {id, name})
(:RefGraph:Product {id, name, type, insurer_id, ...})
```

**Edges:**
```
(Person)-[:DIAGNOSED_WITH {date, confidence, source_doc}]->(Condition)
(Person)-[:PRESCRIBED {date, source_doc}]->(Medication)
(Person)-[:UNDERWENT {date, source_doc}]->(Procedure)
(Condition)-[:OBSERVED_IN]->(Document)
(Product)-[:COVERS]->(Condition)
(Product)-[:EXCLUDES]->(Condition)
(RefGraph node)-[:SAME_AS {confidence, strategy}]->(PrimeKG node)
```

### Hermodr MCP tools (planned)

```
refgraph.entity_at(doc_id, page_num) → entities mentioned on this page
refgraph.entity_neighbors(entity_id, hop=1) → connected entities
refgraph.same_as(entity_id) → PrimeKG equivalent (if linked)
refgraph.path(entity_a, entity_b, max_hops) → connection paths
refgraph.cross_doc(entity_id) → all documents mentioning this entity
```

### Status & next steps

- **S1 execution** (May 19-28 + Jun 2-11): Insurance products → RefGraph → search benchmark
- **Post-S1 (Jun 13+):** generalize for medical records (Underwriter Phase C)
- **Sprint 2 dependency:** RefGraph requires the trait-based extraction from ADR-003 to share types with the rest of the pipeline

## 7. Retrieval Orchestration — How agents use these together

### Pattern 1: Underwriting risk assessment (Eir-router)

```
User: "Assess risk for APP-1234"

Agent steps:
1. underwriter.case_get(APP-1234) → tabular case data + diagnoses + medications
2. refgraph.entity_neighbors(APP-1234, hop=2) → connected entities
   → find: Conditions {T2DM, HTN}, Medications {metformin, lisinopril}
3. For each condition:
   a. primekg.lookup_entity("T2DM") → PrimeKG node id
   b. primekg.neighbors(node_id, relation="contraindication")
      → drugs contraindicated in T2DM
   c. Cross-check against patient's medications (RefGraph) for safety
4. primekg.drug_interactions(metformin) → check against current medications
5. underwriter.fraud_detect(claim history of APP-1234)
6. Synthesize with Eir-cardio (because HTN + T2DM ⇒ cardiac risk specialty)
7. Return: risk_score + per-tool reasoning trace + factor list
```

### Pattern 2: Policy interpretation (insurance underwriter chat)

```
User: "Does Insurer A ProductX cover pre-existing diabetes?"

Agent steps:
1. pageindex.search_pages("pre-existing diabetes", doc_id="ProductX") → top-3 pages
2. pageindex.page_chunks(doc_id, page_47) → full text of relevant page
3. refgraph.entity_at(doc_id, page_47)
   → find: Product { ProductX } -[:EXCLUDES]-> Condition { T2DM (E11.9) }
4. mimir.search_chunks("exclusion clause diabetes ProductX") → vector hits for context
5. Synthesize: "Pre-existing T2DM is excluded; see Section 3.4, page 47. Waiver via underwriting available per Section 3.5."
```

### Pattern 3: Medical chart query (clinician chat with Mega Care portal bridge)

```
User: "ผู้ป่วยรายนี้ควรปรับ CPAP อย่างไร" (patient context: HN-12345)

Agent steps:
1. underwriter.case_get(HN-12345) → patient context (OSA, AHI=35, weight, comorbid HTN)
2. refgraph.entity_neighbors(HN-12345, hop=1) → patient's medications
3. primekg.disease_drugs("Obstructive Sleep Apnea") → guideline-recommended interventions
4. mimir.search_chunks("CPAP titration AHI moderate", filter="medical_guidelines")
5. Route to Eir-sleep specialty agent
6. Eir-sleep reasoning trace + final recommendation
```

## 8. MCP Tool Catalog (consolidated)

Planned tools under Hermodr, organized by namespace:

```
# PrimeKG (medical knowledge)
primekg.lookup_entity(name, type)
primekg.neighbors(entity_id, relation, hop)
primekg.drug_interactions(drug_id)
primekg.disease_drugs(disease_id)
primekg.symptom_to_disease(symptoms)
primekg.path(from_id, to_id, max_hops)

# RefGraph (document-derived KG)
refgraph.entity_at(doc_id, page_num)
refgraph.entity_neighbors(entity_id, hop)
refgraph.same_as(entity_id)
refgraph.path(entity_a, entity_b, max_hops)
refgraph.cross_doc(entity_id)

# PageIndex (long-doc nav)
pageindex.search_pages(query, doc_id?, limit)
pageindex.page_chunks(doc_id, page_num)
pageindex.toc(doc_id)
pageindex.section_chunks(doc_id, section_id)

# Mimir (vector search)
mimir.search_chunks(query, filter, limit)
mimir.search_collection(collection, query, limit)

# Tabular (icd/tmt/tpc lookup)
icd10.lookup(query, mode, locale)
tmt.lookup(query, locale)
tpc.lookup(query, locale)

# Underwriter (Asgard Insurance specific)
underwriter.health_check()
underwriter.case_get(case_id)
underwriter.case_create(applicant_data, files)
underwriter.risk_assess(applicant_id)
underwriter.medical_analyze(applicant_id, doc_refs)
underwriter.fraud_detect(claim_id)
underwriter.decision(applicant_id)
underwriter.portfolio_analytics(filters)
underwriter.hitl_queue_status()

# Syn (OCR)
syn.extract(file_path, lang)
syn.confidence_at(extraction_id, token_id)

# Tyr (audit)
audit.query(time_range, actor, action)
```

**Total:** ~35 tools at full rollout. Many of these are aliases/wrappers around Mimir + Neo4j queries.

## 9. Constraints & Decisions

| Constraint | Source | Impact |
|---|---|---|
| 1 Mac mini per customer, single-tenant | [ADR-009](../decisions/ADR-009-single-tenant-mac-mini-deployment.md) | All indexes per-box; no cross-customer; RefGraph deployment-scoped |
| No cloud LLM unless Skuggi gates | [feedback memory](memory) | All retrieval happens locally; LLM synthesis local by default |
| Rust-first | [memory](memory) | New components (PageIndex, additional tools) prefer Rust impl |
| Local audit via Tyr or LocalDbSink | [ADR-002](../decisions/ADR-002-audit-sink-architecture.md) | Every tool invocation → audit event |
| AGPL + Commercial dual license | [memory](memory) | All shared components publishable to crates.io |
| FHIR R4 canonical types | planned ADR-006 | Tool outputs shape toward FHIR Resources |

## 10. Phased Rollout

### Phase 0 — Foundation (current)
- ✅ PrimeKG in Neo4j (129K nodes)
- ✅ ICD-10-TM anamai 2010 in tabular
- ✅ Syn OCR shipped
- ✅ Skuggi text Tier 1 shipped
- ✅ Eir variants shipped
- 🚫 Qdrant primekg-entities collection NOT populated (P.2 blocked on embedding service)
- 🚫 Chunking has 3 critical issues (chunking audit, fix in Sprint 48)

### Phase 1 — Knowledge Plumbing (Sprint 48 + Sprint 2 prep)
- Fix chunking (PyThaiNLP wire + 800 token default + recursive port + benchmark)
- Embed PrimeKG nodes → Qdrant
- Synthetic Thai applicant generator
- Medical retrieval benchmark queries

### Phase 2 — Agent + MCP Tool Catalog (Sprint 2 Phase C)
- 8 Underwriter MCP tools
- PrimeKG tools (6)
- ICD-10 / TMT / TPC lookup tools
- Hermodr registration + Eir allowlist

### Phase 3 — RefGraph Generalization (post-S1, Sprint 2-3)
- Extract refgraph-rs into asgard-doc-pipeline-refgraph
- 5 RefGraph MCP tools
- SAME_AS pipeline to PrimeKG
- Insurance + medical schema variants

### Phase 4 — PageIndex (Sprint 3+)
- Page-level embedding generation
- Section detection
- 4 PageIndex MCP tools
- Eval benchmark (long-doc retrieval)

### Phase 5 — Unified Retrieval Orchestrator (Sprint 4+)
- Query planner: decide which indexes to hit for a given query
- Multi-tool parallel invocation
- Result fusion (RRF or learned)
- Caching layer (hot queries)

## 11. Open Questions

1. **Page-level embedding aggregation strategy:** mean of chunk embeddings vs LLM-generated page summary embedding? Tradeoff: speed (mean is free) vs quality (summary preserves intent)
2. **RefGraph re-derivation cost:** when a document is re-ingested with better chunking, do we re-extract entities? Likely yes, but need versioning strategy
3. **PrimeKG version pinning vs auto-update:** monthly refresh as planned, or lock per-deployment so customers can validate before adopting new version
4. **Query planner:** rule-based (decision tree of "if asking about X use Y") or learned (LLM-routed)? Rules are auditable; learning adapts. Start with rules.
5. **Tool result caching:** for hot queries (e.g., common drug interactions), cache at Hermodr level or per-Mimir? Latency vs staleness tradeoff
6. **SAME_AS confidence threshold:** when is a name-match good enough? PrimeKG SAME_AS uses 0.9 for name match; need calibration vs Thai names with multiple romanizations

## 12. References

- [ADR-001](../decisions/ADR-001-database-choice.md), [ADR-002](../decisions/ADR-002-audit-sink-architecture.md), [ADR-003](../decisions/ADR-003-shared-doc-pipeline-crate.md), [ADR-009](../decisions/ADR-009-single-tenant-mac-mini-deployment.md)
- [Sprint tracker](../sprint_tracker_2026_05_17.md)
- [PrimeKG data report](../../docs/reference/PRIMEKG_DATA_REPORT.md)
- [Mimir chunking audit memory](memory)
- [AWS QuickSuite comparison memory](memory)
- [refgraph-rs](../../../refgraph-rs/) — S1 active work
- PageIndex pattern: Microsoft Research, "Long-Context Retrieval via Hierarchical Page-Level Indexing" (concept; implementation Asgard-specific)
