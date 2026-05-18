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
| C.6 | ADR — Chunking strategy (post-benchmark decision) | 0.25d | ⬜ | Commit if 800 > 300 by ≥5pp Hit Rate@3 |

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

## ⚡ PrimeKG Qdrant Embedding (~30 min when embedding service up)

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| P.1 | Verify embedding service `host.docker.internal:8001` status | 0.1d | 🚫 | Confirmed DOWN 2026-05-17. localhost:8001 not responding |
| P.1b | Verify Qdrant access path | 0.1d | ✅ | Qdrant pod Running in `asgard-infra`, ClusterIP only → needs port-forward or in-cluster call |
| P.2 | Start embedding service on host (BGE-M3 via FastEmbed or Ollama nomic-embed-text) | 0.25d | 🚫 | NEEDS USER: manual start preferred or document the start procedure |
| P.3 | Trigger PrimeKG node embedding → `primekg-entities` collection | 0.25d | 🚫 | Blocked by P.2 |
| P.4 | Validate: count = ~129K, sample retrieval query works | 0.1d | 🚫 | Blocked by P.3 |

---

## 📆 Window 2 — May 29-Jun 1 (4 days, between S1 phases)

| ID | Task | Effort | Status | Notes |
|---|---|---|---|---|
| W2.1 | Medical retrieval benchmark queries (50-100 TH/EN) | 1d | ✅ | 2026-05-18 M1 dataset shipped — 75 queries (14 categories, TH 25 / EN 48 / mixed 2; easy 19 / medium 36 / hard 20). Registered in eval_benchmark_datasets as `m1_medical_retrieval_v1` (id `10659f35-…`). Includes sleep-specific subset for Mega Care + negation/distractor queries. |
| W2.2 | Send chart sample request to Mega Care | 0.5d | ⬜ | 20-50 de-identified samples + chain of custody |
| W2.3 | TMT/TPC license inquiry to MoPH | 0.5d | ⬜ | Piggy-back ICD-10-TM follow-up |
| W2.4 | FHIR R4 resource selection list (~15 + Thai profile) | 1d | ✅ | 2026-05-18 spec doc at [architecture/fhir_r4_resource_selection.md](architecture/fhir_r4_resource_selection.md). 15 resources locked: Patient/Encounter/Observation/Condition/MedicationRequest/MedicationStatement/Procedure/DiagnosticReport/AllergyIntolerance/DocumentReference + Coverage/Claim/ClaimResponse + Practitioner/Organization. Thai profile constraints for 7 resources. Hand-rolled types recommended over `fhirbolt`. 5 open questions parked for ADR-006. |
| W2.5 | 6 Hermodr MCP tool schemas (JSON spec) | 0.5d | ✅ | 2026-05-18 Hermodr PR #5 MERGED. 6 PrimeKG graph-native tools shipped: primekg_lookup_entity, _neighbors, _drug_interactions, _disease_drugs, _symptom_to_disease, _path. 57/57 tests passing. Mimir backend endpoint impl is separate follow-on. |
| W2.6 | ADR-006 FHIR R4 + Thai coding canonical | 0.5d | ⬜ | |
| W2.7 | Verify MoPH ICD-10-TM 2017 response (due ~May 21) | 0.25d | ⬜ | Decision tree per license-request doc |
| W2.1b | **Synthetic Thai applicants Faker generator** | 2d | ✅ | 2026-05-18 shipped. Path: `Mimir/scripts/synthetic_thai_applicants/`. 7 modules + 19 tests. CLI: `python -m synthetic_thai_applicants --applicants 1000 --claims 500 --seed 42 --output ./out --pdf`. Reproducible seed, Luhn-valid Thai citizen IDs, correlated fraud injection (5 rules), Thai-font PDF medical certificates. Smoke test 50/30 = 17% fraud rate. Delivers I1/I2/X1/M3 dataset inputs. |
| W2.1c | **Dataset inventory plan registration in eval_benchmark_datasets** | 0.5d | 🟡 | 2026-05-18 I1 + I2 registered (1000 applicants + 500 claims, seed=42). Idempotent upsert script at `scripts/register_eval_datasets_i1_i2.py`. Canonical data committed at `tests/eval_datasets/i1/v1.0/`. M1/M4/M8/I5 deferred to separate PRs (each needs its own ground-truth labeling). |

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
| S2.A.1 | Underwriter v3 MariaDB persistence | 5-7d | Per ADR-001; 10 tables incl `chat_sessions`/`audit_events` |
| S2.A.2 | Tyr audit integration | 3-4d | Per ADR-002; LocalDbSink + Wazuh stub + hash chain |
| S2.A.3 | JWT/Yggdrasil auth | 3-4d | Per ADR-009; service-to-service auth, not tenant routing |

### Phase B — Architecture refactor (1-2 weeks)

| ID | Task | Effort | Notes |
|---|---|---|---|
| S2.B.1 | Refactor `extraction.rs` → trait-based | 3-4d | Per ADR-003 |
| S2.B.2 | Extract `asgard-doc-pipeline` workspace + publish v0.1.0 | 3-5d | Per ADR-003; crates.io public AGPL+Commercial |
| S2.B.3 | FHIR R4 types (~15 resources) + Thai profile | 3-5d | Per ADR-006 (pending); ICD-10-TM/TMT/TPC bindings |

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

---

## 🚩 Risks Active

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Embedding service down → PrimeKG Qdrant + B-48f blocked | High (was down 2026-05-07) | Medium | P.1/P.2 priority; FastEmbed local fallback |
| S1 spillover → Window 2 days lost | Medium | High | Cut P1 (W2.6) first |
| MoPH no-response by May 21 | Medium | Medium | International ICD-10 only path |
| Mega Care chart samples slow | High | High | Send request immediately on May 29 |
| Chunking benchmark shows 300 already optimal | Low | Low | Document + close ticket |
| Sprint 2 over-scoped at 5-6 weeks | Medium | Medium | Phase D5-D8 (chat + reasoning UI) are cuttable to Sprint 3 if Phase C delays |
| Faker generator coupling to ICD-10-TM table breaks if schema changes | Low | Low | Pin schema version + test isolation |
| AWS sample evolves and adds patterns worth tracking | Medium | Low | Re-audit aws-samples/sample-quicksuite-chatagent-insurance-underwriting quarterly |

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
