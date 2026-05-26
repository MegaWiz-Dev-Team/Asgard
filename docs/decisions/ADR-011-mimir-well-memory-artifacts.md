# ADR-011: Mimir Well — Memory-Artifact Layer with neo4j-labs Design Borrows

**Status:** Proposed
**Date:** 2026-05-23
**Deciders:** paripol@megawiz.co
**Scope:** Sprint 56 implementation of the `mimir-well` Mimir submodule (memory artifact accumulation primitive). Layers on top of existing Mimir RAG, PrimeKG, `heimdall-trace`, and `mimir-curator`. Does not change deployment model ([ADR-009](ADR-009-single-tenant-mac-mini-deployment.md)) or the agents-vs-skills boundary ([ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md)).
**Supersedes:** the v1 Sprint 56 schema sketch in `docs/sprints/syn-dicom-plan.md` §S56 — this ADR is the canonical design for that sprint.

## Context

Asgard has RAG (Mimir), KG (PrimeKG), tenant surfaces, and trace (`heimdall-trace`) — but **no accumulation primitive**. RAG is stateless lookup; nothing in the stack today encodes:

- "Asgard learned this last week" (episodic)
- "Insurer X's underwriting policy semantically connects to this medical record" (semantic)
- "Last time a similar case came in, this 6-step procedure worked" (procedural)

The gap matches Tulving's 3-tier memory taxonomy (episodic / semantic / procedural). Reference implementations exist in the field: Letta/MemGPT, Zep/Graphiti (bitemporal Neo4j, P95 ~300ms), Cognee (memory control plane), and most recently **neo4j-labs/agent-memory** (graph-native, Apache 2.0, polished SDK + 16-tool MCP).

We reviewed neo4j-labs/agent-memory in detail (2026-05-23 session). Its core ideas are sound and align with our Tulving plan. **We adopt the design patterns; we do NOT vendor the library** because (a) it is Python/TypeScript (violates Rust-first), (b) Apache 2.0 dependency in core would dilute the AGPL+Commercial moat, and (c) it ships features (Wikipedia/Diffbot enrichment, geospatial) we do not need.

This ADR locks the five borrowed ideas and adds a hard backup-first operational invariant.

## Decision

Build `mimir-well` as a Rust submodule of Mimir, exposing a 3-tier artifact store (MariaDB rows + Neo4j mirror), with the following five borrowed designs and one operational invariant:

### D1. Three tiers, dual-labeled (Tulving primary, neo4j-labs UX surface)

| `tier` (storage) | `surface` (UX label) | Example |
|---|---|---|
| `episodic` | Short-term | "Case A23 on 2026-05-23: Eir answered HCC staging question" |
| `semantic` | Long-term | "Tenant `asgard_medical` trusts ESC-2024 HTN guideline" |
| `procedural` | Reasoning | "Underwriting flow for BMI>35+smoker → 4-step Tier-3 quote" |

Tulving labels in schema/code; neo4j-labs short/long/reasoning labels in UI and MCP tool descriptions (more approachable for analyst users).

### D2. `:TOUCHED` audit edges = materialized view of `heimdall-trace`

Every Bifrost step that reads or writes an artifact emits an OTel span attribute:

```json
{
  "asgard.well.touched": [
    { "artifact_id": "01J...", "role": "used" },
    { "artifact_id": "01J...", "role": "generated" },
    { "artifact_id": "01J...", "role": "refined" },
    { "artifact_id": "01J...", "role": "contradicted" }
  ]
}
```

An async worker on the `heimdall-trace` side projects these into Neo4j as `(:Span)-[:TOUCHED {role, ts}]->(:Artifact)`. We do not duplicate trace storage; Neo4j holds only `(trace_id, span_id)` pointers back to Laminar.

Procedural artifacts are derived: when a span chain completes successfully + user-rated positively, the chain is promoted to a procedural artifact with the decision graph as content.

### D3. Consolidation = scored + curator-gated (NOT on-write)

The neo4j-labs `consolidation.dedupe_entities()` primitive is adopted as a **separate async worker** (`mimir-well-consolidator`) feeding `mimir-curator`'s Label Studio. Three tiers:

| Similarity / state | Path |
|---|---|
| `content_hash` match | auto-merge, no curator |
| cosine ≥ 0.98 (within tenant+tier) | auto-merge, post-hoc audit log |
| 0.92 ≤ cosine < 0.98 | curator review queue (`well-consolidation` project) |
| `CONTRADICTS` edge detected | high-priority queue → recursive deep-research per Mimir Curator runbook |

Worker has two modes: `DryRun` (logs intended merges, requires `--confirm-apply` to write) and `Apply`. Ingest path stays fast (target P95 < 300ms à la Zep/Graphiti); consolidation is fully async.

### D4. POLE+O ontology — `asgard_insurance` only

POLE+O (Person / Object / Location / Event / Organization) is a clean fit for insurance underwriting (insureds, policies, claim events, hospitals, insurers).

| POLE+O | `asgard_insurance` entity | Neo4j sub-label |
|---|---|---|
| Person | insured, beneficiary, doctor, agent | `:Artifact:Person` |
| Object | policy, rider, claim doc, med cert | `:Artifact:Policy` / `:Claim` / `:Document` |
| Location | branch, hospital, incident site | `:Artifact:Location` |
| Event | application, UW decision, claim event | `:Artifact:Event` |
| Organization | insurer, reinsurer, hospital, employer | `:Artifact:Organization` |

**Scope rule:** POLE+O labels are applied only when `tenant_id = 'asgard_insurance'`. `asgard_medical` continues to use PrimeKG (biomedical-grade); forcing POLE+O on clinical data would degrade existing biomedical relationships.

### D5. Bifrost memvid stays as session scratchpad; long-term flows to Mimir Well

The existing `Bifrost/src/memory/memvid_manager.rs` (148 LOC, `.mv2` per `(agent_id, session_id)`) remains as **ephemeral working memory** — microsecond-latency local lookup, session-bound, default TTL 24h.

On session end (or explicit `commit_to_well` tool call), a new `Bifrost/src/memory/promotion.rs` (~150 LOC) POSTs frames + span tree + outcome to `/mimir/well/promote`. A small classifier (gemma-4-1b local) tags each frame as `drop` / `episodic` / `semantic` / `procedural` and writes accepted artifacts to Mimir Well. Bifrost README §long-term-memory line is corrected to clarify the split.

### D6. Backup-first operational invariant (HARD GATE)

Every execution path of this design that mutates persistent state MUST start with an explicit backup, and the plan/runbook MUST list the backup step — no implicit / assumed backups. Sprint 56 ships `scripts/backup-neo4j-only.sh` (already in repo as of this ADR) as the cheaper-than-full pre-flight for Neo4j-only changes.

**Per-task backup requirement (Sprint 56 task table):**

| Sprint 56 task | Backup before? | Why |
|---|---|---|
| MariaDB schema migration | full backup | irreversible ALTER |
| Neo4j POLE+O labels | `backup-neo4j-only.sh TAG=pre-pole-o` | bulk MERGE |
| `mimir-well` crate (code) | none | reversible |
| PROV-O → Tyr emitter | none | append-only |
| Consolidator first Apply run | snapshot ≤24h old | merges destructive |
| `:TOUCHED` bulk materialization | `backup-neo4j-only.sh TAG=pre-touched` | bulk MERGE |
| First Bifrost prod promotion | snapshot ≤24h old | new data path |
| Hermodr MCP tools | none | code only |
| UI `/mimir/well` | none | read-only |
| Eval harness | none | reads only |

Sprint exit criterion: a successful **restore drill** in a scratch namespace. `scripts/restore-from-backup.sh` (~200 LOC) is in-sprint scope if it does not yet exist.

## Schema (canonical for Sprint 56)

```sql
CREATE TABLE mimir.memory_artifact (
  id CHAR(26) PRIMARY KEY,                    -- ULID
  tenant_id VARCHAR(64) NOT NULL,
  agent_id VARCHAR(64) NOT NULL,
  case_id VARCHAR(64) NULL,
  kind ENUM('observation','abstraction','skill','correction','reference') NOT NULL,
  tier ENUM('episodic','semantic','procedural') NOT NULL,
  surface ENUM('short','long','reasoning') NOT NULL,
  content_hash CHAR(64) NOT NULL,
  content JSON NOT NULL,
  embedding BLOB NULL,
  prov_used JSON NULL,
  prov_generated_by VARCHAR(255) NULL,
  confidence DECIMAL(4,3) NULL,
  promoted_from VARCHAR(64) NULL COMMENT 'Bifrost session id if promoted',
  consolidation_state ENUM('fresh','reviewed','superseded','contradicted')
    NOT NULL DEFAULT 'fresh',
  superseded_by CHAR(26) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_tenant_tier (tenant_id, tier, surface, created_at),
  INDEX idx_consolidation (tenant_id, consolidation_state),
  INDEX idx_content_hash (tenant_id, content_hash)
);

CREATE TABLE mimir.well_consolidation_queue (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  tenant_id VARCHAR(64) NOT NULL,
  artifact_a CHAR(26) NOT NULL,
  artifact_b CHAR(26) NOT NULL,
  similarity DECIMAL(4,3) NOT NULL,
  kind ENUM('near_dup','contradiction') NOT NULL,
  ls_task_id BIGINT NULL,
  decided_at TIMESTAMP NULL,
  decision ENUM('merge','keep_both','supersede','flag_conflict') NULL,
  INDEX (tenant_id, decided_at)
);
```

```cypher
CREATE INDEX artifact_tenant_tier IF NOT EXISTS FOR (a:Artifact) ON (a.tenant_id, a.tier);
CREATE INDEX span_lookup IF NOT EXISTS FOR (s:Span) ON (s.trace_id, s.span_id);

// :TOUCHED is the new edge from heimdall-trace materialization
// :DERIVED_FROM, :USED_IN, :REFINES, :CONTRADICTS already in v1 plan
```

## MCP surface (Hermodr `well_*`)

- `well_search(query, tier?, surface?, tenant_scope?)`
- `well_consolidate_run(mode='DryRun'|'Apply', tenant_id)`
- `well_supersession_chain(artifact_id)`
- `well_touched_by(artifact_id)` — returns `heimdall-trace` deeplinks
- `well_consolidation_queue_stats(tenant_id)`

## Sprint placement

S56 (per `docs/sprints/syn-dicom-plan.md`). Gated by:

1. S1 Go/No-Go (2026-06-12) — medical retrieval Hit Rate@3 ≥ 75%
2. S52-54 Insurance Launch + Cloud stable
3. S55 Mimir Guideline Lineage shipped

Estimated effort: ~3,600 LOC + 200 LOC (`restore-from-backup.sh` if absent) + ~30 min runtime overhead from backup gates per execution.

## What we explicitly do NOT borrow from neo4j-labs

| Their feature | Reason |
|---|---|
| Wikipedia / Diffbot enrichment | PII risk + non-Thai sources; PrimeKG + curator cover this |
| Geospatial queries | No current use case; reserve for S58+ if claims-by-region arises |
| spaCy / GLiNER / GLiREL pipeline | Asgard uses Thai PyThaiNLP + Heimdall LLM; do not add English NER stack |
| LiteLLM universal fallback | Heimdall already routes providers per ADR scope |
| Python + TypeScript SDKs | Asgard is Rust-first; expose via Hermodr MCP instead |
| `EmbeddingConfig`/`LLMConfig` provider strings | Heimdall is the provider abstraction; do not duplicate |

## Consequences

**Positive:**
- Closes the accumulation gap that competitors (MIKAI etc.) exploit
- 3-tier model gives clear UX surface for "what did Asgard learn"
- Reusing `heimdall-trace` for `:TOUCHED` avoids duplicate provenance store
- Backup-first invariant prevents the "small migration" class of data loss
- POLE+O bounded to insurance keeps medical tenant clean

**Negative:**
- ~3,600 LOC + restore script — meaningful sprint commitment
- Tier classifier (gemma-4-1b) adds inference cost on every session-end promotion
- Backup gates add ~30 min per execution → maintenance windows required
- Two ontologies (PrimeKG for medical, POLE+O for insurance) means tooling must branch on tenant

**Neutral / TBD:**
- Tier classifier accuracy needs empirical validation before promotion path goes prod
- Auto-merge threshold (0.98) is a defensible default but should be reviewed after 1 month of curator data
- Procedural-artifact promotion criterion ("user-rated positively") needs a rating UX

## Open questions

1. Should POLE+O labels be sub-labels on `:Artifact` or a parallel label tree (`:POLE_Person`) to avoid clashing with PrimeKG?
2. Curator capacity for the `well-consolidation` queue — auto-merge ≥0.95 if no curator available in S56?
3. Promotion trigger: auto on session end, explicit `commit_to_well` tool, or both?
4. Tier classifier model — gemma-4-1b enough, or escalate to gemma-4-26b for ambiguous frames?

## References

- `docs/sprints/syn-dicom-plan.md` §S56 (sprint plan)
- `docs/decisions/ADR-009-single-tenant-mac-mini-deployment.md`
- `docs/decisions/ADR-010-agents-as-boundaries-skills-as-expertise.md`
- `scripts/backup-neo4j-only.sh` (added with this ADR)
- `scripts/backup-full-k8s.sh`
- `Bifrost/src/memory/memvid_manager.rs`
- neo4j-labs/agent-memory (Apache 2.0, design reference only — not a dependency)
- PROV-AGENT (arXiv:2508.02866, IEEE eScience 2025) — provenance standard
- Tulving (1972, 1985) — episodic / semantic / procedural taxonomy
- Zep / Graphiti — bitemporal Neo4j memory P95 ~300ms benchmark reference