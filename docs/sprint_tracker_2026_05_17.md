# Sprint Tracker — Asgard Foundation Prep (2026-05-17)

**Created:** 2026-05-17
**Duration:** 2026-05-17 → 2026-06-12 (Foundation Prep) + Jun 13+ (Sprint 2)
**Owner:** solo execution
**Status:** 🟢 ACTIVE

Legend: ⬜ pending · 🟡 in-progress · ✅ done · 🚫 blocked · ❌ cancelled

---

## 🎯 Active execution order

1. Sprint 48 chunking remediation (concurrent with active Sprint 48)
2. Window 1 ADRs (May 17-18)
3. PrimeKG Qdrant embedding (when embedding service up)
4. Window 2 tasks (May 29-Jun 1)
5. Sprint 2 kickoff (Jun 13+, Phase A.1 shift +1 week)

---

## 🔧 Sprint 48 — Chunking Remediation (~3.5 days)

Pick-up reason: B-48f Qdrant Thai semantic search is deferred; Fix #1 unblocks it.

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| C.1 | Thai-aware sentence segmentation in Rust chunking.rs | 0.5d | ✅ | 2026-05-17: Python ingest pipeline not in main (only in v1.0.0-s1-insurance-sprint tag); fixed at Rust `services/chunking.rs::split_by_sentences` instead. Added Thai paiyannoi (ฯ), newline, and whitespace-after-Thai as boundaries. 5/5 integration tests pass at `tests/chunking_thai.rs`. mimir-core-ai 0.2.0 → 0.2.1. **Full HTTP PyThaiNLP wire deferred** — requires async refactor of sync split_by_sentences API. Unblocks B-48f Qdrant Thai semantic search. |
| C.2 | Replace token estimator `chars/4` with proper tokenizer | 0.5d | ✅ | 2026-05-17: PR [#300](https://github.com/MegaWiz-Dev-Team/Mimir/pull/300). Used HuggingFace `tokenizers` crate (Rust-First), lazy-loaded via `BGE_M3_TOKENIZER_PATH` env, graceful fallback to chars/4. Independent of #299. mimir-core-ai 0.2.0 → 0.2.2. 3/3 integration tests pass on both env-set and env-unset paths. |
| C.3 | Insurance chunk size default 300 → 800 tokens | 0.25d | ⬜ | After C.5 benchmark confirms; touch: `phase1_extraction.py:19-20`, `phase1_extraction_s2.py` |
| C.4 | Port Rust recursive chunker logic into Python pipeline | 1d | ⬜ | Or call Rust via API; preserves markdown hierarchy |
| C.5 | Benchmark matrix: chunk_size × overlap × language on Hit Rate@3 | 1d | ✅ | 2026-05-18 PR [#301](https://github.com/MegaWiz-Dev-Team/Mimir/pull/301). Sprint 48 v0 18 queries: baseline semantic-only **61.1%** vs full cascade **100.0%** (+38.9pp). Cascade matches production icd10.rs path. Quick wins 1+2+3 already in main; this PR is proof-of-correctness benchmark. **Bonus:** restored `icd10_codes` table (15,376 rows from Qdrant payloads — was empty after Sprint 51e rotation). Full chunk-size matrix (size×overlap×lang) NOT applicable to icd10-th (single-row chunks); defer to pubmed-abstracts/insurance corpus sprint. |
| C.6 | ADR-005 Chunking strategy (post-mortem) | 0.5d | ✅ | 2026-05-18 [ADR-005](decisions/ADR-005-chunking-strategy.md). Locks recursive + Thai-aware + BGE-M3 tokenizer strategy. Documents Sprint 48 outcome (C.1 + C.2 + C.5 shipped, C.3 + C.4 N/A in main), 4 lessons learned, forward plan (long-doc matrix deferred, PyThaiNLP HTTP async refactor deferred, semantic chunking Sprint 10 placeholder). |

**Decision gate (C.5):** ≥5pp improvement → switch default. Else stay 300, document why.

---

## 📅 Window 1 — May 17-18 (2 days, NOT blocked by S1)

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| W1.1 | Verify PrimeKG Qdrant state | 0.5d | ✅ | Confirmed: code exists ([routes/admin_knowledge.rs:152,214](Mimir/ro-ai-bridge/src/routes/admin_knowledge.rs)) but never RUN. Collection `primekg-entities` (1024-dim) ready to populate |
| W1.2 | Read MegaCare TriParty PoC TechBrief | — | ❌ | Out of scope per user 2026-05-17 |
| W1.3 | Read Sprint 48 progress doc | 0.5d | ✅ | Done — 4/10 backlog shipped, B-48f deferred (embedding service down), B-48a license pending |
| W1.4 | Read Multi-Agent Architecture Plan | 0.5d | ⬜ | P1, optional |
| W1.5 | ADR-001 DB choice (MariaDB) | 0.25d | ✅ | [ADR-001](decisions/ADR-001-database-choice.md) — 2026-05-17 |
| W1.6 | ADR-002 Audit sink architecture | 0.25d | ✅ | [ADR-002](decisions/ADR-002-audit-sink-architecture.md) — 2026-05-17 |
| W1.7 | ADR-003 Trait-based extraction + shared crate boundary | 0.5d | ✅ | [ADR-003](decisions/ADR-003-shared-doc-pipeline-crate.md) — 2026-05-17 |
| W1.8 | ADR-009 Single-tenant per Mac mini deployment model | 0.25d | ✅ | [ADR-009](decisions/ADR-009-single-tenant-mac-mini-deployment.md) — 2026-05-17 |

---

## ⚡ PrimeKG Qdrant Embedding — DONE 2026-05-18

**Unblocked + completed end-to-end in this session.** The "P.1 embedding service down" blocker was stale — it referred to a deprecated Ollama/FastEmbed setup. Heimdall BGE-M3 (`:8080/v1/embeddings`) was already running and is the correct path per `feedback_no_ollama`. Also discovered Neo4j was empty (Sprint 51e rotation reaped the PVC); re-imported.

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| P.0 | **NEW**: Re-import PrimeKG → Neo4j (lost in Sprint 51e rotation) | 0.5d | ✅ | 2026-05-18 17:13–17:19 (6m36s real time via `Mimir/scripts/primekg_import.sh`). 129,375 nodes + 8.1M edges via APOC LOAD CSV. SAME_AS pass 0 links (no `:Entity` nodes populated yet — expected). |
| P.1 | ~~Verify embedding service `host.docker.internal:8001`~~ — stale ref | — | ❌ | Cancelled; Heimdall `:8080/v1/embeddings` is the canonical path. |
| P.1b | Verify Qdrant access path | 0.1d | ✅ | Qdrant pod Running in `asgard-infra`, ClusterIP → port-forward `:6333:6333`. |
| P.2 | ~~Start embedding service on host~~ | — | ❌ | Cancelled; Heimdall launchd services already up. |
| P.3 | Trigger PrimeKG node embedding → `primekg-entities` collection | 0.25d | ✅ | 2026-05-18 via `POST /api/v1/admin/knowledge/primekg/embed`. **NB: Mimir API process needs `NEO4J_PASSWORD` env or it silently retries auth + returns `total=0`.** Also note `routes/icd10.rs` was still calling Ollama — fixed in Mimir PR #306. |
| P.4 | Validate: count + sample retrieval query | 0.1d | ✅ | Qdrant `primekg-entities` = 129,374 points (1 below Neo4j due to a duplicate `entity_index` in PrimeKG kg.csv; not a defect). Sample queries verified: `"diabetes mellitus"` → diabetes (disease) top 5; Thai `"ปวดศีรษะ"` → "Pain in head and neck region" / "Headache" (cross-lingual via BGE-M3). |
| P.5 | **NEW**: Shared Knowledge Bases endpoint + UI | 1.0d | ✅ | 2026-05-18 Mimir PR #308 — `GET /api/v1/knowledge/shared` lists ICD-10-TM / PrimeKG / LOINC / TMT / TPC with live counts; dashboard page at `/knowledge/shared`. Resolves user ask "primekg ต้องเห็นใน UI". |

---

## 📆 Window 2 — May 29-Jun 1 (4 days, between S1 phases)

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| W2.1 | Medical retrieval benchmark queries (50-100 TH/EN) | 1d | ✅ | 2026-05-18 M1 dataset shipped — 75 queries (14 categories, TH 25 / EN 48 / mixed 2; easy 19 / medium 36 / hard 20). Registered in eval_benchmark_datasets as `m1_medical_retrieval_v1` (id `10659f35-…`). Includes sleep-specific subset for Mega Care + negation/distractor queries. |
| W2.2 | Send chart sample request to Mega Care | 0.5d | ⬜ | 20-50 de-identified samples + chain of custody |
| W2.3 | TMT/TPC license inquiry to MoPH | 0.5d | ⏭️ | 2026-05-18 user direction: skip waiting; proceed with anamai 2010 + LOINC free; TMT/TPC ingest may use alternative sources or wait passively for any future MoPH response |
| W2.3a | **LOINC ValueSet ingest** | 1.5d | ⬜ | NEW (G2 gap). Free download from loinc.org; no license needed. Migration table `loinc_codes`; ingest script + audit row in pattern of `icd10_tm_anamai_ingest.py`. Powers `Observation.code` validation in B.3. **Not blocked.** |
| W2.3b | **TMT ValueSet ingest** | 1d | 🚫 | NEW (G2 gap). Thai Medicines Terminology; powers `MedicationRequest.medicationCodeableConcept` Thai profile. **Blocked: no licensed source confirmed.** Per 2026-05-18 user direction, do NOT wait on MoPH; investigate alternative sources (NHSO open data, RxNorm proxy, hospital partner institutional license) before/during S2.B.3. If still unresolved at B.3 ship: MedicationRequest accepts any CodeableConcept; Thai profile validation relaxes from "required" to "recommended" until data exists. |
| W2.3c | **TPC ValueSet ingest** | 0.5d | 🚫 | NEW (G2 gap). Thai Procedural Classification; powers `Procedure.code` Thai profile. **Same block as W2.3b.** Same fallback: Procedure.code accepts any CodeableConcept; Thai profile validation downgrades when no data. |
| W2.3d | **Coding validator service** | 1d | ⬜ | NEW (G2 gap). `validate_coding(system, code)` over the 4 master tables (icd10_codes + loinc_codes + tmt_codes + tpc_codes — whichever are populated). Used by FHIR validation in Phase B.3 + Eir agents calling `read_fhir` tool. Returns Unknown/Validated/SystemMissing per binding. Depends on at least W2.3a + icd10_codes populated. |
| W2.4 | FHIR R4 resource selection list (~15 + Thai profile) | 1d | ✅ | 2026-05-18 spec doc at [architecture/fhir_r4_resource_selection.md](architecture/fhir_r4_resource_selection.md). 15 resources locked: Patient/Encounter/Observation/Condition/MedicationRequest/MedicationStatement/Procedure/DiagnosticReport/AllergyIntolerance/DocumentReference + Coverage/Claim/ClaimResponse + Practitioner/Organization. Thai profile constraints for 7 resources. Hand-rolled types recommended over `fhirbolt`. 5 open questions parked for ADR-006. |
| W2.5 | 6 Hermodr MCP tool schemas (JSON spec) | 0.5d | ✅ | 2026-05-18 Hermodr PR #5 MERGED. 6 PrimeKG graph-native tools shipped: primekg_lookup_entity, _neighbors, _drug_interactions, _disease_drugs, _symptom_to_disease, _path. 57/57 tests passing. Mimir backend endpoint impl is separate follow-on. |
| W2.6 | ADR-006 FHIR R4 + Thai coding canonical | 0.5d | ✅ | 2026-05-18 Asgard PR #67 MERGED. [ADR-006](decisions/ADR-006-fhir-canonical-design.md) locks 5 W2.4 open questions. Phase B.3 effort refined to 10-12d (was 3-5d optimistic). 10-step implementation order specified. |
| W2.7 | Verify MoPH ICD-10-TM 2017 response (due ~May 21) | 0.25d | ⏭️ | 2026-05-18 user direction: skip; proceed with anamai 2010 in production + LOINC free. Do not block any downstream work on MoPH response. |
| W2.1b | **Synthetic Thai applicants Faker generator** | 2d | ✅ | 2026-05-18 shipped. Path: `Mimir/scripts/synthetic_thai_applicants/`. 7 modules + 19 tests. CLI: `python -m synthetic_thai_applicants --applicants 1000 --claims 500 --seed 42 --output ./out --pdf`. Reproducible seed, Luhn-valid Thai citizen IDs, correlated fraud injection (5 rules), Thai-font PDF medical certificates. Smoke test 50/30 = 17% fraud rate. Delivers I1/I2/X1/M3 dataset inputs. |
| W2.1c | **Dataset inventory plan registration in eval_benchmark_datasets** | 0.5d | ✅ | 2026-05-18 Mimir PR #303 MERGED. I1 + I2 registered (1000 applicants + 500 claims, seed=42). Idempotent upsert script at `scripts/register_eval_datasets_i1_i2.py`. Canonical data committed at `tests/eval_datasets/i1/v1.0/`. M1/M4/M8/I5 deferred to separate PRs (each needs its own ground-truth labeling). M1 itself shipped via #304. |

---

## 🚪 Window 3 — Jun 12 (Sprint gate)

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| W3.1 | Sprint review + Sprint 2 lock | 0.25d | ⬜ | Update plan based on Window 1-2 results |
| W3.2 | S1 RefGraph go/no-go (external) | — | ⬜ | Per S1 plan, gate day |

---

## 🚀 Sprint 2 Preview (Jun 13+, NOT committed yet)

**Phase A.1 shifted +1 week → starts Jun 20** (was Jun 13)
**Total Sprint 2 effort:** ~5-6 weeks (up from 4) after AWS sample learnings absorbed into Phase C/D

### Phase A — Foundation (3 weeks)

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.A.0 | **Partial FHIR types in Underwriter** (Patient + Encounter) — Option C per G4 resolution 2026-05-18 | 1-1.5d | NEW. Lives at `asgard-underwriter/iris/src/fhir/` temporarily; relocates to `asgard-doc-pipeline-core` during S2.B.2. Also rename `iris::underwriting::Condition` → `PolicyCondition` to free the `Condition` name for FHIR. Unblocks A.1 schema to be FHIR-shape-aware instead of JSON blob. |
| S2.A.1 | Underwriter v3 MariaDB persistence | 5-7d | Per ADR-001; 10 tables incl `chat_sessions`/`audit_events`. Now schema-aligned with A.0 Patient/Encounter types; remaining domain (Condition/Medication/Procedure/etc.) stored as FHIR JSON columns in patient_record table until B.3 lands typed schema. |
| S2.A.2 | Tyr audit integration | 3-4d | Per ADR-002; LocalDbSink + Wazuh stub + hash chain |
| S2.A.3 | JWT/Yggdrasil auth | 3-4d | Per ADR-009; service-to-service auth, not tenant routing |

### Phase B — Architecture refactor (1-2 weeks)

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.B.1 | Refactor `extraction.rs` → trait-based | 3-4d | Per ADR-003 |
| S2.B.2 | Extract `asgard-doc-pipeline` workspace + publish v0.1.0 | 3-5d | Per ADR-003; **standalone repo `MegaWiz-Dev-Team/asgard-doc-pipeline`** (decision 2026-05-18); crates.io public AGPL+Commercial. See readiness checklist below. |
| S2.B.3 | FHIR R4 types (~15 resources) + Thai profile | **10-12d** | Per ADR-006 (locked); 15 resources + 12 datatypes + Thai profile bindings + External* newtypes + schema export. Effort refined from 3-5d in ADR-006. Depends on A.0 Patient/Encounter (already typed) + W2.3a-d coding tables (parts may degrade to "any CodeableConcept" if TMT/TPC unavailable). |

### S2.B.2 readiness checklist (decided 2026-05-18)

| Item | Status | Action |
|---|---|---|
| Repo location | ✅ standalone `MegaWiz-Dev-Team/asgard-doc-pipeline` (not monorepo) | Create empty repo before S2.B.2 starts |
| crates.io account + publish token | ✅ token detected in `~/.cargo/credentials.toml` | Verify scope before first publish |
| AGPL-3.0 + Commercial dual license boilerplate | ⬜ | Author at S2.B.2 start; mirror Asgard top-level legal repo format |
| Cargo workspace skeleton (7 sub-crates per ADR-003 §B.2) | ⬜ | First commit of new repo |
| README + LICENSE-AGPL.md + LICENSE-COMMERCIAL.md | ⬜ | Same |
| GitHub Actions CI for crates.io publish on tag | ⬜ | Optional; manual publish OK for v0.1.0 |

### Phase C — Production hardening + MCP tool catalog (~3 weeks)

**EXPANDED from AWS sample analysis** — added C.5-C.9 (fraud detection + analytics + MCP wrap)

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.C.1 | Multi-insurer product comparison (Prudential/ThaiLife/Thai Health) | 5-6d | S2 architecture, dedup >0.95 |
| S2.C.2 | HITL queue production (SLA, assignment, escalation) | 3d | Reuse from Phase A.1 schema |
| S2.C.3 | Observability (prometheus + OTel + JSON logs) | 3d | Per ADR-005 (pending) |
| S2.C.4 | PDF export depth | 3d | Keep `printpdf`; add ICD-10/timeline/HITL notes |
| **S2.C.5** | **Fraud detection heuristic engine** | 2d | NEW from AWS sample. Correlated patterns: short-policy + high-amount, repeat-claimant, status-investigating |
| **S2.C.5b** | **`underwriter.fraud_detect(claim_id)` MCP tool** | 0.5d | NEW. Eir reasoning explanation layer |
| **S2.C.6** | **Portfolio analytics aggregation queries** | 1.5d | NEW. Risk distribution, claims trends, fraud trend, throughput |
| **S2.C.6b** | **`underwriter.portfolio_analytics(filters)` MCP tool** | 0.5d | NEW |
| **S2.C.7** | **Wrap existing workflows as 5 MCP tools** | 1.5d | NEW. health/risk_assess/medical_analyze/decision/case_create |
| **S2.C.8** | **Register 8 tools in Hermodr + Eir allowlist** | 0.5d | NEW |
| **S2.C.9** | **Tool invocation audit (every call → audit_events)** | 0.5d | NEW; uses Phase A.2 audit pattern |

### Phase D — Polish + UX adoptions (~2 weeks)

**EXPANDED from AWS sample analysis** — added D.5-D.8 (reasoning UI + chat panel + tool viz + deep mode)

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.D.1 | Frontend test coverage (4/12 → ≥10/12) | 2-3d | |
| S2.D.2 | Benchmarks (k6 load test, SLO definition) | 2d | |
| S2.D.3 | Server-mode Docker | 2d | |
| S2.D.4 | ADR backfill | 1d | ADR-004/005/006/007/008/010 |
| **S2.D.5** | **Reasoning trace UI** (collapsible per-agent in Assessment + ExtractionReview) | 2d | NEW. Quick Suite-inspired explainability |
| **S2.D.5b** | **Backend: per_agent_reasoning field in risk response** | 0.5d | NEW. Depends C.7 |
| **S2.D.6** | **Case-scoped chat panel** — design + SSE protocol | 1d | NEW. Per [cloudflare_timeout_sse memory](memory) — SSE not WebSocket |
| **S2.D.6b** | **Backend: ChatSession + multi-turn Eir-router** | 2d | NEW |
| **S2.D.6c** | **Frontend `<CaseChatPanel/>` component** | 1.5d | NEW. Streaming + tool invocation visible |
| **S2.D.7** | **Tool invocation visualization in HITLQueue** | 1.5d | NEW. Reads audit_events |
| **S2.D.8** | **Deep mode toggle** (high reasoning effort) | 1d | NEW. Maps to Heimdall maxReasoningEffort |

### Carryover from Sprint 48

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.W2.1 | PrimeKG benchmark + runbook | 3-5d | Remaining W2 Phase 1 tasks |
| S2.CO.1 | Chunking remediation rollout (if Sprint 48 unfinished) | — | Carryover |

---

## 🚀 Sprint 3 Preview — FHIR Consumer Integration (NOT committed yet)

**Theme:** Wire the FHIR types from Sprint 2 B.3 into actual consumers — Eir agents (read), OCR pipeline (write), Underwriter workflow (write). FHIR stops being a library; it becomes a live data shape across the platform.

**Prereq:** Sprint 2 complete. Specifically required:
- S2.B.3 (FHIR R4 types + Thai profile) shipped to `asgard-doc-pipeline-core`
- W2.3a (LOINC ingest) ✅ powering `Observation.code` validation
- W2.3d (coding validator) ✅ so emitted FHIR resources pass validation
- S2.A.1 (Underwriter MariaDB persistence) ✅ so Claim emission has case data to reference

**Total effort:** ~10-13d (2-3 weeks calendar)
**Calendar window:** after Sprint 2 ships, target mid-to-late July 2026

### F-track: FHIR consumer wiring

| ID | Task | Effort | Notes |
|---|---|---|---|
| S3.F.1 | **Eir `read_fhir` Hermodr tool wired to Eir Gateway (OpenEMR FHIR API)** | 2-3d | Adds real implementation behind the `read_fhir` tool allowlist entry in `Eir/docs/Eir_Agents_Architecture.md` §3.1. Touch: `Hermodr/src/services/eir_medical.rs` (add ToolDefinition + endpoint route); upstream = Eir Gateway OpenEMR FHIR REST API (`GET /apis/default/fhir/Patient/{id}`, `Condition?patient={id}`, etc.). Auth: OpenEMR uses OAuth2; Hermodr proxies with service credentials. Returns canonical `asgard-doc-pipeline-core` Patient/Condition/etc. (not raw OpenEMR JSON). Tests: happy path + 404 + auth fail + ExternalPatient → Patient conversion path. **Unblocks all Eir specialty agents from doing real FHIR reads instead of placeholders.** |
| S3.F.2 | **OCR pipeline → FHIR Bundle mapper** | 3-4d | New module `asgard-doc-pipeline-pipeline::ocr_to_fhir`. Input: `ExtractionResult` (from Syn OCR + Mimir entity linking + PrimeKG validation). Output: FHIR Bundle containing Patient (from extracted identifiers) + Encounter (visit shell) + Conditions (extracted dx, ICD-10-TM coded) + MedicationRequests (extracted Rx, TMT coded if available) + Procedures (TPC coded) + DocumentReference (pointer to source scan). Handles low-confidence extractions: `Condition.verificationStatus = "provisional"`. Internal Bundle references resolved via URL fragments (`Patient/local-1`, `Condition/local-2` referencing `Patient/local-1`). Validation: emitted Bundle passes coding-validator (W2.3d) + Thai profile constraints. Tests: 10-20 fixture extractions → expected Bundles snapshot-compared. **Sets up M3 OCR benchmark to score against FHIR-shape output instead of bespoke extraction JSON.** |
| S3.F.3 | **Underwriter → FHIR Claim/ClaimResponse emitter** | 2-3d | New module `asgard-underwriter::fhir_claim_emitter`. Input: case + final UnderwritingDecision after assessment. Output: FHIR Claim (with linked Patient + diagnoses-as-Condition references + procedures + supporting_info pointing to DocumentReferences) + ClaimResponse (adjudication outcome — accepted/denied/refer-to-HITL, with risk_score → `adjudication[].amount` mapping). Wires into Underwriter workflow as the FINAL step after HITL approval (or auto-approve for high-confidence cases). PDF export path can use the Claim/ClaimResponse pair as its data source. Tests: 5-10 case fixtures → expected Claim/Response snapshot. **Closes the loop on underwriting being FHIR-native, not bespoke schema.** |
| S3.F.4 | **FHIR conformance test corpus + harness** | 2d | Test corpus: ~50 hand-crafted FHIR Bundles covering each of the 15 resources + Thai profile edge cases (citizen_id Luhn, multi-language HumanName, missing coding-when-validator-not-loaded). Harness: validates each Bundle against `asgard-doc-pipeline-core` schemas + Thai profile constraints + coding-validator (W2.3d). Living as test_eval_datasets entry. Run on every PR touching `asgard-doc-pipeline-core` or any of S3.F.1-3. **Catches Thai profile drift + schema-Validation/coding-validator regressions.** |
| S3.F.5 | **Bundle round-trip benchmark** (optional) | 1d | Benchmark: take a `Patient` (or Bundle) → serialize to JSON → parse back → assert identity. Measures schema completeness (any field that doesn't round-trip = schema missing). Run on M3 OCR-emitted Bundles + S3.F.4 hand-crafted Bundles. **Only run if S3.F.4 surfaces unexpected diffs; otherwise defer.** |

### Sprint 3 dependency graph

```
S2.B.3 (FHIR types)  ──┬─→ S3.F.1 (Eir read)
                       ├─→ S3.F.2 (OCR write)
                       └─→ S3.F.3 (Underwriter write)
                              ↓
                       S3.F.4 (conformance test corpus + harness)
                              ↓
                       S3.F.5 (round-trip bench, optional)

W2.3a (LOINC)          ──→ S3.F.2 (Observation validation)
W2.3d (coding val)     ──→ S3.F.2, S3.F.3 (emit-time validation)
S2.A.1 (Underwriter DB) ──→ S3.F.3 (case data to reference)
S3.F.4 (corpus)         ──→ Eir per-specialty HBp% baselines (M6 dataset)
```

S3.F.1/F.2/F.3 are independent of each other — can run in any order or parallel (3 different code surfaces). F.4 consolidates.

### Open questions parked for Sprint 3 kickoff

1. **Eir Gateway OAuth flow** — does Hermodr terminate the OAuth dance with OpenEMR, or does it forward a JWT issued by Yggdrasil that OpenEMR accepts? (Likely first; the second requires OpenEMR config we may not control.)
2. **Bundle storage in Underwriter** — does S3.F.3 emit Bundle to a new `bundles` MariaDB table, or stream into Tyr audit only, or both? (Likely both — Tyr for audit, table for retrieval.)
3. **Claim adjudication numeric mapping** — `risk_score 0-100` to `ClaimResponse.adjudication[].amount`? Or use a custom extension? FHIR doesn't have a native "risk score" field; need decision.
4. **M3 OCR benchmark scoring** — once S3.F.2 ships, M3 hit-rate scores against Bundle outputs (per-field) or whole-Bundle equality? Per-field is more informative; needs scoring spec.
5. **HITL UI for FHIR-shape data** — does the reviewer see Bundle JSON, rendered FHIR card, or canonical Underwriter UI? Likely keep current UI; Bundle is back-end shape only.

---

## 📝 Decision Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-05-17 | DB = MariaDB first (not Postgres-everywhere) | Bifrost stack stable, blast radius too high |
| 2026-05-17 | Audit sink = LocalDbSink + Wazuh stub | Local first, Wazuh ready for when Tyr scales up |
| 2026-05-17 | crates.io public for shared crate | AGPL+Commercial dual license; open-core moat |
| 2026-05-17 | Keep `printpdf` | Stability over polish (typst nicer but switch cost too high) |
| 2026-05-17 | Insurers: Prudential, ThaiLife, Thai Health | NOT AXA; user correction |
| 2026-05-17 | 1 Mac mini per customer, on-prem single-tenant | No RBAC, tenant_id is deployment config |
| 2026-05-17 | Embedding runtime = candle + Metal recommended | Rust-First, no architecture split (vs MLX which needs host service split) |
| 2026-05-17 | FHIR R4 canonical + Thai coding (ICD-10-TM/TMT/TPC) | Cross-domain interop free if both sides speak FHIR |
| 2026-05-17 | Display names "Asgard Medical" / "Asgard Insurance" | Tech tenant_id stays snake_case; dual-name like Laminar/Sága |
| 2026-05-17 | Chunking remediation → Sprint 48 (not Sprint 2) | Unblocks B-48f Qdrant Thai search |
| 2026-05-17 | Phase A.1 shift +1 week (Jun 13 → Jun 20) | Chunking remediation absorbs 5 days |
| 2026-05-17 | AWS sample analysis → adopt Faker, 6 MCP tools (+2 new), 4 UX patterns | Phase C adds fraud + analytics + MCP wrap (+5d); Phase D adds reasoning trace + chat + tool viz + deep mode (+8d); Sprint 2 grows 4→5-6 weeks |
| 2026-05-17 | Adopt 8-tool MCP catalog over Hermodr (mirror AWS pattern) | health/risk/medical/fraud/decision/analytics/case_create/hitl_status. External-facing for future portal bridges |
| 2026-05-17 | Case-scoped chat uses SSE (not WebSocket) | Per `cloudflare_timeout_sse` memory — proven pattern, CF-friendly |
| 2026-05-17 | Faker generator output includes synthetic PDFs (not just JSON) | Asgard pipeline tests OCR; AWS sample is JSON-only |
| 2026-05-17 | Faker fraud_indicators must be correlated (not random) | AWS sample uses pure random which doesn't train/test fraud detection meaningfully |
| 2026-05-17 | Heimdall #10 + Mimir #294/#295/#297/#298 merged. Mimir tagged v1.4.0; Heimdall tagged v0.7.0 (NOT v0.6.0 due to existing legacy tag conflict from Hotswap fix May 5). Stacked-merge via #298 brought entire JWT chain. | Backend SSO release ships locked. Production deploy unblocks via [deploy runbook in commit 72d9483](https://github.com/MegaWiz-Dev-Team/Mimir/commit/72d9483) |
| 2026-05-18 | **G2 gap resolution: add W2.3a-d for LOINC + TMT + TPC ingest + coding validator** | Phase B.3 FHIR types require coding-system validation. Without these, ships schema-only. LOINC unblocked (free); TMT/TPC blocked on alternative source discovery (license deferred per user). |
| 2026-05-18 | **G5 gap resolution: skip MoPH license waiting → proceed with anamai 2010 + LOINC + alternative TMT/TPC sources** | User direction. Day 21 escalation deadline (2026-05-28) deprioritized; alternative paths (NHSO open data / RxNorm proxy / hospital-partner institutional license) explored during S2.B.3 instead of synchronous blocking. |
| 2026-05-18 | **G4 gap resolution: Option C — Partial FHIR (Patient + Encounter typed in Phase A.0)** before A.1 schema | Avoids JSON-blob → typed migration in Phase B.3; freed `Condition` name from `iris::underwriting` namespace clash; types relocate to `asgard-doc-pipeline-core` during S2.B.2. |
| 2026-05-18 | **G1 gap resolution: `asgard-doc-pipeline` = standalone repo `MegaWiz-Dev-Team/asgard-doc-pipeline`** (NOT monorepo workspace) | Cleaner external contribution surface; independent versioning; crates.io publishing simpler. AGPL+Commercial dual license boilerplate authored at S2.B.2 start. |

---

## 🚩 Risks Active

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Embedding service down → PrimeKG Qdrant + B-48f blocked | High (was down 2026-05-07) | Medium | P.1/P.2 priority; FastEmbed local fallback |
| S1 spillover → Window 2 days lost | Medium | High | Cut P1 (W2.6) first |
| MoPH no-response by May 21 | Medium | Medium | ~~International ICD-10 only path~~ ⏭️ Per 2026-05-18 user direction: deprioritized. Proceed with anamai 2010 + LOINC free + alternative TMT/TPC sources. |
| Mega Care chart samples slow | High | High | Send request immediately on May 29 |
| Chunking benchmark shows 300 already optimal | Low | Low | Document + close ticket |
| Sprint 2 over-scoped at 5-6 weeks | Medium | Medium | Phase D5-D8 (chat + reasoning UI) are cuttable to Sprint 3 if Phase C delays |
| Faker generator coupling to ICD-10-TM table breaks if schema changes | Low | Low | Pin schema version + test isolation |
| AWS sample evolves and adds patterns worth tracking | Medium | Low | Re-audit aws-samples/sample-quicksuite-chatagent-insurance-underwriting quarterly |
| **TMT / TPC source not found before B.3 ship** | Medium | Medium | NEW. Fallback: Thai profile validation downgrades from "required" to "recommended" for MedicationRequest + Procedure. Investigation tasks during W2.3b/c — try NHSO open data, RxNorm as Thai-equivalent proxy, hospital-partner institutional license. |
| **SMART on FHIR (RS384 keypair) needed when Prudential POC has FHIR API** | Medium | Medium | NEW. No ADR yet — defer until Prudential tech brief lands. Mark in Phase D backlog. |
| **HL7 v2 ingress (parser + MLLP + mapper + HOSxP quirks) needed for first hospital customer** | Medium | High when needed | NEW. No design now — wait until first customer specifies vendor + version (HOSxP / HIS-Plus / Bizzcomm / in-house). Then scope sprint. |
| **`iris::underwriting::Condition` namespace clash with FHIR `Condition`** | Medium (will hit) | Low | NEW. Rename to `PolicyCondition` as part of S2.A.0 (early Phase A). Pre-emptive, not after-the-fact. |

---

## 📎 References

- [feedback_tenant_is_domain_not_org](memory)
- [underwriter_v3_plan_decisions](memory)
- [mimir_chunking_audit](memory)
- [PrimeKG data report](docs/reference/PRIMEKG_DATA_REPORT.md)
- [Sprint 48 progress](Mimir/docs/03_implementation_plans/sprint48_progress_2026-05-07.md)
- [ICD-10-TM license request](Asgard/legal/2026-05-07_MoPH_ICD-10-TM_License_Request.md)
- AWS sample (competitor analysis): https://github.com/aws-samples/sample-quicksuite-chatagent-insurance-underwriting
- [Solution architecture — Agent/MCP/RAG/Graph/PageIndex/RefGraph](architecture/agent_rag_graph_solution_architecture.md)
- [Evaluation dataset inventory plan 2026-05-17](../../Mimir/docs/04_evaluation_and_testing/04_10_dataset_inventory_plan_2026-05-17.md)
