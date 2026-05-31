# Medical Agent Redesign — Design Index (handoff)

**Status:** Design complete, **not yet implemented**, docs **not yet committed**
(except the Bifrost memory note). **Date:** 2026-05-22.

**One-line decision:** Replace "19 cloned specialty agents + LLM router" with
**5 boundary agents + retrieved skills**. Agent = enforceable trust/policy
boundary (few); Skill = expertise module selected by embedding (many).
Authoritative decision = [ADR-010].

---

## The documents (read in this order)

| # | Doc (absolute path) | What it is |
|---|---------------------|------------|
| 1 | `/Users/mimir/Developer/Asgard/docs/decisions/ADR-010-agents-as-boundaries-skills-as-expertise.md` | **Decision record** — the why + the rule. Start here. |
| 2 | `/Users/mimir/Developer/Eir/docs/design/medical-agent-architecture.md` | Architecture — 5-agent roster, skill model, **§4b deterministic agent-resolver**, safety, migration. |
| 3 | `/Users/mimir/Developer/Eir/docs/design/medical-agent-data-model.md` | Schema (`agent_configs` changes, `agent_skills` table, `skills-catalog` Qdrant) + 19→5 migration. |
| 4 | `/Users/mimir/Developer/Eir/docs/design/knowledge-tool-layer.md` | Tool catalog (8 PrimeKG routes + ICD-10/SNOMED/MONDO) → how skills declare tools + `knowledge_scope`. |
| 5 | `/Users/mimir/Developer/Bifrost/docs/design/skill-loader-runtime.md` | The one net-new component: skill-loader in the Bifrost overseer (select → compose → intersect tools). |
| 6 | `/Users/mimir/Developer/Bifrost/docs/design/agent-memory-evolution.md` | Context compaction + Memvid PDPA erasure (shares the progressive-disclosure budget). **Committed** on branch `docs/agent-memory-evolution`. |
| — | `/Users/mimir/Developer/Eir/docs/Eir_Agents_Architecture.md` | The OLD 19-agent doc — now carries a banner pointing here; treat its roster as the "source to port into skills". |

---

## The 5 boundary agents
`eir-clinical` (default host), `eir-pharmacy` (mandatory Rx gate), `eir-pediatrics`
(dosing safety), `eir-psychiatry` (safety floor), `eir-emergency` (latency).
**`eir-forensic` deferred** (no platform RBAC per ADR-009 to enforce access).

## Hard invariants (do not violate when implementing)
1. Skill selection = **retrieval, not LLM** (reuse BGE-M3 + Qdrant).
2. Skills **only NARROW** — never expand tool ceiling, weaken safety, or go cloud.
3. **Degrade to bare agent** if registry/selection unavailable.
4. **LOCAL-LLM only** + single-tenant-per-box (ADR-009) unchanged.
5. Agent selection (§4b) is **deterministic + safety-critical**, never silently downgrades.

## Build order
- **Phase 0:** the 4 blockers are already resolved in the docs (agent-resolver,
  forensic deferred, ceiling defined, model_hint→allowed_models).
- **Phase 1 (MVP):** `agent_skills` + ingest + `skills-catalog` + `/api/v1/skills/select`
  + loader injects `reasoning_frame` only (no tool/agent change). Parity-test on
  a non-safety subset.
- **Phase 1.5:** deterministic agent-resolver (needed before peds/pharmacy go live).
- **Phase 2:** tool intersection + dispatch deny + Tyr.
- **Phase 3:** `knowledge_scope` + clinical-wisdom specialty backfill.
- **Phase 4:** progressive disclosure + real token counter.
- **Phase 5:** migrate 19→5, retire `eir-router`, scale skills.
- **Parallel/independent:** Memvid PDPA erasure; PrimeKG `resolve()` SQL-injection
  fix (handled in another session); context compaction.

## Open items (specify before the phase noted)
- `safety_class` behaviour table (HITL/refusals) — before Phase 2.
- clinical-wisdom `specialty` payload backfill — before Phase 3.
- first-turn age/intent signal extraction for §4b — **structured/deterministic on
  safety branches (FHIR age, UI order-intent); no NLP intent classification** — before Phase 1.5.
- PrimeKG tools `{items,count}` → standard ToolResult envelope.
- **Consistency migration:** convert `primekg-graph-assistant` (agent id=9 @
  `asgard_platform`) → a `graph-explorer` **skill** on that tenant's default host
  (arch §9b). Live change — owner executes; cross-tenant access stays a tenant/box
  boundary (ADR-009), not an agent boundary.
- ✅ ~~`primekg_resolve` SQL-injection prereq~~ **DONE** (mimir-api v2.3.43:
  `.bind()` + `escape_like()`, verified). `resolve`/`disease_relations` safe for untrusted text.

## Cross-session review log
- **2026-05-22** — PrimeKG-owner session reviewed; endorsed ADR-010. Incorporated:
  SQLi prereq closed; agent-9 anti-pattern → graph-explorer skill (§9b); global
  assistant uses §4b deterministic resolution not an LLM router; §4b safety
  branches must use structured signals; `reasoning_frame` made advisory +
  score-floored + subordinate to safety preamble; Phase-2 deny-by-default must be
  co-tested with the bypass injector.

## Git status
Nothing committed except the memory note. To hand off cleanly, the design docs
**must** be committed (uncommitted = handoff risk; other sessions won't see them).
Eir + Asgard use Conventional Commits; branch per repo. The **design-owning
session commits** (avoid clobbering another session's staged work).