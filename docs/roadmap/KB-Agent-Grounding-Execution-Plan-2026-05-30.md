# Execution Plan — Wire Medical KBs into Eir Agents (R2 + R3)

**Date:** 2026-05-30
**Status:** Bifrost code DONE (compiles); Mimir route + Hermodr arg-map + coordinated redeploy PENDING
**Owner:** (assign) · **Reviewers:** Bifrost + Mimir maintainers
**Tenant:** `asgard_medical` · **Scope:** Eir 20-agent swarm

---

## 1. Executive summary

The 8 medical KBs (ICD-10-TM, PrimeKG, LOINC, TMT, TMLT, SNOMED→ICD-10-TM, TPC,
Abbreviation glossary) are **NOT wired into the Eir agent runtime.** Agents
currently ground only on generic `golden_qa` + `source_chunks` vector chunks —
no PrimeKG, no code resolvers. This was proven by benchmark (§3) and traced to a
**multi-layer gap stack** (§4). Licenses are all cleared (§7), so this is purely
an engineering task. This plan lists the exact fix per layer; the Bifrost change
is already implemented and compiles.

---

## 2. Benchmark evidence (baseline, in Mimir eval)

Harnesses (new, reusable): `Mimir/scripts/agent_swarm_mcq_bench.py`,
`agent_swarm_healthbench.py`, `judge_bench.py`, `rejudge_healthbench.py`.

| Benchmark | Result | run_id | Reading |
|---|---|---|---|
| MCQ MedQA n=20 (exact-match) | all 19 agents + swarm = **80.0%** | `2180bade…` | base model dominates; prompts don't move MCQ |
| HealthBench-oss n=10 (Gemini judge) | 14.1–23.5%; **swarm 23.5%** (avoids weak agent); ob-gyn 14.1% | `6534cca1…` | open-ended differentiates a little; spread narrow |
| Judge bench (controlled) | gemini-2.5/3.5-flash/3-flash-preview all **F1=1.00**, consistent | — | judge model not a differentiator (thinkingBudget=0 locked) |

**Why the spread is narrow:** every agent grounds on the SAME generic chunks (no
KB-specific grounding) + shares the gemma-4-26b base. HealthBench absolute % is
low because agents answer in Thai vs English rubric → use RELATIVE, not absolute.

**Acceptance for "after":** re-run `agent_swarm_healthbench.py` post-deploy; expect
PrimeKG-grounded specialists to rise and spread to widen vs baseline `6534cca1`.

---

## 3. The gap stack (root-caused from code, 2026-05-30)

| # | Layer | Finding | File evidence |
|---|---|---|---|
| G1 | **Bifrost overseer** | `bypass_tools=true` for provider=heimdall (ALL our agents) → the ReAct/MCP dynamic-tool block is skipped entirely | `Bifrost/src/swarm_engine/overseer.rs` (`if !bypass_tools`) |
| G2 | **Bifrost overseer** | Only 5 tools implemented: `vector_search`/`graph_search`/`tree_search`/`memvid_agent_memory_search`/`ocr_extract`. All other tool names → "unknown tool — skipping" | overseer.rs match block |
| G3 | **Bifrost skills** | `VectorSearchTool` collections HARDCODED `["golden_qa","source_chunks"]` → never searches ICD-10-TM (15.4K) / PrimeKG (129K) Qdrant points | `skills.rs` VectorSearchTool::new call in overseer.rs:~253 |
| G4 | **Bifrost skills** | `graph_search` uses `SqlGraphRetriever` (MariaDB bridge), NOT Neo4j → PrimeKG 8.1M-edge graph unreachable | `retrieval/graph.rs` |
| G5 | **agent_configs** | 14/20 agents `tools=NULL` (vector RAG fallback only); 5 boundary agents had tool names WITHOUT `vector_search` → **RAG silently OFF** (the 21.8% cluster) | `agent_configs` query |
| G6 | **Hermodr-mimir** | `tools/call search_primekg` → upstream **HTTP 404** | `Hermodr/src/services/mimir.rs` path=`/api/v1/knowledge/primekg` |
| G7 | **Mimir (running)** | `/api/v1/knowledge/primekg` route exists in SOURCE (`ro-ai-bridge/src/main.rs:248`) but **running binary is older → 404 live**. SNOMED route exists (live). | probe: GET/POST → 404; snomed → 405 |
| G8 | **Arg schema drift** | KB tools differ: SNOMED resolver wants `{"text": …}`, not `{"query": …}` | probe: snomed POST → "missing field `text`" |

---

## 4. Fixes per layer

### ✅ Bifrost (DONE — compiles, SQLX_OFFLINE=true)
Implemented on branch (see §6). Addresses G1/G2 for query-based KB tools:
- `skills.rs`: new `HermodrKbTool` (generic: query → `hermodr-mimir /rpc tools/call` → Mimir) + `kb_tool_label()` map.
- `overseer.rs`: in the `bypass_tools` manual-context path, loop over `agent_tools`; for each query-based KB tool, call `HermodrKbTool` and inject `[label]:\n{result}` into context before generation.
- Env: `HERMODR_MIMIR_URL` (default `http://hermodr-mimir.asgard.svc:8090/rpc`).
- Architecture choice: Bifrost calls Mimir via Hermodr HTTP (Mimir already owns Neo4j/Qdrant/mariadb) — no Neo4j crate added to Bifrost, no client duplication.

**Still open in Bifrost (do alongside Mimir fix):**
- **G8 arg-map:** `HermodrKbTool` sends `{query}`. For tools whose Mimir handler expects a different field (e.g. SNOMED `text`), add per-tool arg mapping in `HermodrKbTool::call` or normalize the Mimir handler to accept `query`. Recommend: normalize Mimir handlers to accept `query` (single convention).
- (Optional, larger) G3/G4: add medical KB Qdrant collections to `VectorSearchTool` + wire Neo4j graph retriever — only if HTTP-tool grounding proves insufficient.

### Mimir (PENDING — required for R3 to work)
- **G7:** rebuild + redeploy Mimir so the running binary includes `/api/v1/knowledge/primekg` (already in `main.rs:248`). Verify live: `POST /api/v1/knowledge/primekg {"query":"…"}` → 200.
- **G8:** confirm/normalize arg field across `/knowledge/{primekg,snomed,tmt,tmlt,...}` to a single `query` key (or document each).

### Hermodr (PENDING — verify)
- **G6:** confirm `mimir.rs` catalog paths match the live Mimir routes after redeploy; fix any path mismatch.

### agent_configs (DONE — safe, reversible)
- **G5:** all 19 non-router agents set to `["vector_search","search_primekg","search_clinical_kb"]`. Backup: `/tmp/agent_configs_tools_backup_2026-05-30.sql`. Safe under old binary (unknown tools ignored; `vector_search` re-enables RAG on boundary agents). Tune per-specialty later.

---

## 5. Execution order (coordinated release)

1. **Bifrost:** review + merge branch (§6) → build image `bifrost:<sha>` → `kubectl -n asgard set image deploy/bifrost bifrost=bifrost:<sha>` (imagePullPolicy=Never → local docker image; **verify image ID after rollout**).
2. **Mimir:** rebuild + redeploy so `/knowledge/primekg` is live (G7); normalize arg schema (G8).
3. **Hermodr:** verify catalog paths vs live Mimir (G6); redeploy if changed.
4. **Verify chain:** temp curl pod → `tools/call search_primekg` via `hermodr-mimir` → expect 200 with PrimeKG hits.
5. **Re-benchmark:** `GEMINI_API_KEY=… python3 Mimir/scripts/agent_swarm_healthbench.py --n 10 --split oss_eval --seed 42` → compare to baseline `6534cca1`.

## 6. Bifrost code change
Branch: `feat/kb-agent-grounding` (off `docs/agent-memory-evolution` @ f9c716d).
Files: `src/swarm_engine/skills.rs`, `src/swarm_engine/overseer.rs`. Builds with
`SQLX_OFFLINE=true cargo build -p bifrost` (local mimir-core-ai needs offline sqlx
cache; the 24 "Connection refused" errors are sqlx compile-time DB checks, not real).

## 7. Licensing
All medical KB licenses CLEARED for commercial ship (2026-05-30): SNOMED Affiliate,
PrimeKG/DrugBank, LOINC, ICD-10-TM 2017, TPC-Thai. No tier-gating needed. One
recurring obligation: SNOMED Affiliate requires upgrade ≤180 days (biannual).
`Hermodr/DATA_LICENSE.md` still says "commercial gating" — update to cleared.

## 8. Acceptance criteria
- [ ] `POST /api/v1/knowledge/primekg` returns 200 on running Mimir
- [ ] `hermodr-mimir tools/call search_primekg` returns PrimeKG hits (not 404)
- [ ] Bifrost agent `/run` for a clinical query shows `[PrimeKG Knowledge Graph]` in context (trace/log)
- [ ] HealthBench re-run shows measurable lift / wider spread vs `6534cca1`
- [ ] No regression in latency budgets (emergency ≤2s p50 etc.)
