# ADR-005: Chunking Strategy — Sprint 48 Outcome + Forward Plan

**Status:** Accepted
**Date:** 2026-05-18
**Deciders:** paripol@megawiz.co
**Scope:** Mimir RAG chunking + tokenization across all collections
**Related:** [mimir_chunking_audit memory](../../../.claude/projects/-Users-mimir-Developer/memory/mimir_chunking_audit.md), Sprint 48 chunking remediation PRs (Mimir #299/#300/#301), [solution architecture](../architecture/agent_rag_graph_solution_architecture.md)

## Context

Sprint 48 (Thai Clinical Coding Foundation) included a chunking remediation track. The 2026-05-17 audit found 3 issues:

1. **Thai sentence splitter English-only** — `split_by_sentences` in `services/chunking.rs` recognized only `.`/`!`/`?`. Thai paragraphs degraded to `fixed_fallback` (mid-character cuts), producing fragmented BGE-M3 embeddings.
2. **Insurance chunk size 300 tokens** — `phase1_extraction.py:19-20` used `chunk_size = 300` with `chars/4` heuristic. BGE-M3 has 8192-token context, so this was 27× too small for Thai (which is ~1 token/char in BGE-M3 BPE, not 0.25).
3. **Recursive chunker bypassed** — Rust `chunking.rs` had a recursive chunker (heading → paragraph → sentence → fixed fallback) but Python ingest used naive `split("\n\n")`, losing markdown hierarchy.

This ADR locks the chunking strategy that emerged from the sprint, documents what was shipped vs N/A, and sets forward direction.

## Decision

### 1. Chunking strategy = **Recursive with Thai-aware sentence splitter, BGE-M3 tokenizer-backed sizing**

The canonical chunker is `chunking::chunk_recursive` in [`Mimir/ro-ai-bridge/mimir-core-ai/src/services/chunking.rs`](https://github.com/MegaWiz-Dev-Team/Mimir/blob/main/ro-ai-bridge/mimir-core-ai/src/services/chunking.rs):

```
Heading (## / ###)  →  Paragraph (\n\n)  →  Sentence (Thai-aware)  →  Fixed fallback
```

Sentence splitter recognizes:
- Latin: `.`, `!`, `?`
- Thai paiyannoi `ฯ`
- Newline `\n`
- Soft boundary: whitespace immediately after a Thai character (PyThaiNLP-style heuristic, regex-based)

Size sizing uses the real BGE-M3 tokenizer when `BGE_M3_TOKENIZER_PATH` env var points to a `tokenizer.json`. Falls back to `chars/4` heuristic when unset.

**Default chunk sizes (in tokens, post-BGE-M3-tokenization):**

| Document type | Size | Overlap | Rationale |
|---|---|---|---|
| Insurance policy | 800 | 80 (10%) | Future change when Python ingest returns to main; rule-spans-section need 600-1000 tokens. Currently 300 in Python tag-only code (not in main). |
| Medical chart text | 500 | 50 (10%) | Mid-size; matches typical clinical section length |
| PrimeKG node text | n/a | n/a | 1 node = 1 vector; not chunked (text ~80 chars) |
| ICD-10-TM code text | n/a | n/a | 1 row = 1 vector; not chunked (text ~100 chars) |
| PubMed abstract | 500 | 50 | Abstract length typically 200-400 tokens; single chunk usually |
| Clinical guideline | 800 | 80 | Larger sections; preserve clinical reasoning units |

These are the **target** defaults. Validation against a real chunk-size matrix is deferred (see §3 below).

### 2. Tokenization = **real BGE-M3 tokenizer** when configured, **`chars/4` fallback** otherwise

Implementation in [Mimir #300](https://github.com/MegaWiz-Dev-Team/Mimir/pull/300):

```rust
static BGE_M3_TOKENIZER: OnceLock<Option<Tokenizer>> = OnceLock::new();

pub fn estimate_tokens(text: &str) -> usize {
    match bge_m3_tokenizer() {
        Some(tk) => tk.encode(text, false).map(|e| e.len()).unwrap_or_else(|_| estimate_tokens_fallback(text)),
        None => estimate_tokens_fallback(text),
    }
}

pub(crate) fn estimate_tokens_fallback(text: &str) -> usize {
    (text.len() as f64 / 4.0).ceil() as usize
}
```

Operator setup (post-deploy):

```bash
export BGE_M3_TOKENIZER_PATH=/path/to/Heimdall/gateway/.fastembed_cache/models--BAAI--bge-m3/snapshots/<sha>/tokenizer.json
```

The fastembed cache already populates this file when BGE-M3 is first used in Heimdall.

### 3. Cascade retrieval for ICD-10 = **`exact → naive → semantic`** with acronym expansion

For the ICD-10 lookup specifically (a different concern from general-purpose chunking but relevant to retrieval quality): the cascade pattern in [`routes/icd10.rs`](https://github.com/MegaWiz-Dev-Team/Mimir/blob/main/ro-ai-bridge/src/routes/icd10.rs) is the production answer:

1. **exact** — SQL `code = ?` or `label = ?`
2. **naive** — SQL `LIKE %q%`
3. **semantic** — Qdrant vector search after `expand_acronyms()` preprocesses the query

Measured Hit Rate@3 on Sprint 48 v0 (18 queries): **100% (18/18)** via full cascade vs 61.1% via semantic-only direct ([Mimir #301](https://github.com/MegaWiz-Dev-Team/Mimir/pull/301), 2026-05-18).

This cascade is ICD-10-specific. Other corpora (PrimeKG, clinical-wisdom, source_chunks) use direct semantic search; the cascade pattern is a future tool if those corpora show similar failure modes.

## Sprint 48 outcome — what shipped vs what was N/A

| Task | Status | What happened |
|---|---|---|
| **C.1** Thai sentence splitter | ✅ Mimir #299 | Added paiyannoi (`ฯ`) + newline + whitespace-after-Thai. 5 integration tests. mimir-core-ai 0.2.0 → 0.2.1. |
| **C.2** BGE-M3 tokenizer | ✅ Mimir #300 | HuggingFace `tokenizers` crate + lazy OnceLock load via env. 3 integration tests covering both env-set and env-unset paths. mimir-core-ai 0.2.1 → 0.2.2. |
| **C.3** Insurance chunk 300 → 800 | ❌ N/A | Audit-identified file `insurance_ingestion_s2/phases/phase1_extraction.py` is NOT in main (only in `v1.0.0-s1-insurance-sprint` tag, archived sprint snapshot). When Python ingest returns to main, apply C.3 then. |
| **C.4** Port recursive to Python | ❌ N/A | Same reason as C.3 — Python ingest not in main. |
| **C.5** Benchmark matrix | ✅ Mimir #301 | Pivoted from chunk-size matrix to cascade benchmark (chunk-size matrix not applicable to single-row chunks in icd10-th). Delivered Sprint 48 v0 baseline 61.1% → cascade 100% (+38.9pp). |
| **C.6** ADR-005 (this doc) | ✅ this PR | Locks chunking strategy + post-mortem. |

**Bonus deliverables that emerged:**

| Bonus | Outcome |
|---|---|
| icd10_codes table restoration | Discovered table was empty in main (Sprint 51e rotation reset). Restored 15,376 rows from Qdrant icd10-th payloads via `scripts/restore_icd10_from_qdrant.py`. Production cascade now actually works (was silently failing — SQL modes returned empty before). |
| Cascade pattern was already in main | The "Quick wins 1+2+3" we proposed (hybrid retrieval, acronym dict, ranking weight) were already shipped during Sprint 48's quiet work. C.5 benchmark proved they work as designed. Saved an estimated 3d of re-implementing. |

## Lessons learned

### 1. The original audit overshot — half the issues weren't in main

The audit was performed by a sub-agent that grep'd across the repo. It included files in `insurance_ingestion_s2/phases/` which were archived in `v1.0.0-s1-insurance-sprint` tag only — never merged to main. **Two of the three issues didn't apply to current production code.**

**Implication:** for future audits, restrict scope to `main` (or specify branch); use `git log` to verify recent changes; cross-check that grep hits represent live code, not tag-only snapshots.

### 2. The "wins" were already shipped — we measured what already existed

Sprint 48 had quietly shipped:
- Cascade `auto → exact → naive → semantic`
- Acronym expansion dictionary (34 entries)
- `ORDER BY (code = ?) DESC, (code LIKE ?) DESC, CHAR_LENGTH ASC, code ASC` ranking

But these wins were invisible — the C.5 baseline benchmark (61% semantic-only) made it look like the cascade hadn't shipped. Only when we measured the actual cascade did we get 100%.

**Implication:** when a sprint ships behavioral improvements, ship a benchmark too. Otherwise the next sprint can't tell what's already done.

### 3. Schema/state can vanish between sprints

The `icd10_codes` table was populated by Sprint 48 B-48d Phase A (2026-05-07) with 15,376 rows. By 2026-05-18 the table was empty in main — the Sprint 51e rotation reset state. Qdrant retained the data because Qdrant ingest happened separately.

**Implication:** for any state populated by ingest scripts, document the restore path. A "how to restore X if rotation wipes it" runbook should accompany every ingest. We have `restore_icd10_from_qdrant.py` now; future ingests should follow the same pattern.

### 4. Pivoting the benchmark scope was correct

We planned a 5×3×3 = 45-config chunk-size matrix. Reality: icd10-th has single-row chunks (no chunk-size dimension applies). We pivoted to the cascade benchmark instead.

**Implication:** don't run a benchmark just because it was planned. If the corpus doesn't have the property the benchmark measures, pick a corpus that does (pubmed-abstracts for chunk size, defer to a future sprint) or pick a different benchmark.

## Alternatives considered

### Chunking strategy alternatives

- **Fixed-size only**: simple but loses structure; rejected — recursive is barely more code and respects markdown hierarchy.
- **Semantic chunking via LLM**: deferred to Sprint 10 (planned in `ChunkStrategy::Semantic` variant in chunking.rs; currently returns error). LLM cost per chunk decision is high; recursive is "good enough" until validated otherwise.
- **External PyThaiNLP service**: full integration would require async refactor of `split_by_sentences` (sync now). The regex approximation in C.1 covers most cases. Wire to PyThaiNLP HTTP endpoint when async refactor sprint lands.

### Tokenizer alternatives

- **`tiktoken-rs`**: targets OpenAI BPE, not BGE-M3 vocab. Wrong tokenizer for our embedder.
- **HuggingFace `tokenizers` crate (chosen)**: matches BGE-M3 exactly; same crate the embedder uses internally.
- **Always-`chars/4` heuristic**: catastrophic for Thai (over-counts 3-4×); produces wrong chunk sizes that fragment embeddings.

### Cascade alternatives (ICD-10 specifically)

- **Pure semantic (chars/4 baseline)**: 61% Hit Rate@3 on Sprint 48 v0; under the M1 60-75% hybrid gate.
- **Pure SQL (no semantic)**: misses Thai natural-language queries (`ปวดหัว` → R51 via semantic) and acronym queries (`STEMI` via expansion).
- **Cascade with acronym expansion (chosen)**: 100% Hit Rate@3.

## Consequences

### Positive

- **Thai retrieval works** — was silently broken (mid-char cuts); now produces valid embeddings
- **Token accounting accurate** — chunk-size budgets actually match what the embedder sees
- **ICD-10 cascade validated** — 100% baseline proves the cascade architecture is correct; no fine-tune needed
- **Production cascade actually works** — `icd10_codes` table populated; SQL modes return results

### Negative

- **Python ingest C.3 / C.4 still pending** — when Python pipeline returns, apply chunk size 300 → 800 and recursive port
- **No long-doc chunk-size benchmark yet** — pubmed-abstracts (196K points) and insurance docs unbenchmarked for chunk-size sensitivity; deferred to a future sprint
- **PyThaiNLP HTTP integration deferred** — regex approximation is "good enough" but not perfect Thai sentence segmentation

### Risks accepted

- **Chunk size defaults are educated guesses, not benchmark-validated** — the 800-token insurance + 500-token medical numbers come from the M1 dataset plan + analogous BGE-M3 best practices. If a future benchmark shows they're wrong, we change them — easy update.
- **`BGE_M3_TOKENIZER_PATH` setup is operator action** — if unset, falls back to `chars/4` (worse for Thai). Document in deploy runbook; verify in K8s readiness probe.

## Forward plan

### When to revisit chunking

1. **Real long-doc chunk-size matrix** — when pubmed-abstracts retrieval or insurance-doc retrieval performance is questioned. Use `c5_cascade_retrieval.py` pattern as harness skeleton.
2. **Python ingest C.3 / C.4** — if/when `insurance_ingestion_s2` returns to main (currently archived in tag).
3. **PyThaiNLP HTTP integration** — when the async refactor sprint lands. The regex approximation suffices for now.
4. **Semantic chunking via LLM** — Sprint 10 placeholder. Triggers if benchmark shows recursive chunking is the dominant retrieval-quality bottleneck.
5. **PageIndex** — separate workstream (per solution architecture §5) for long-doc page-level retrieval; not a chunk-size question, an indexing strategy.

### What to NOT revisit

- The Thai-aware sentence splitter regex (works; if it doesn't, fix in place, no design change needed)
- The cascade pattern for ICD-10 (validated 100%; don't break what works)
- The BGE-M3 tokenizer integration (works; if a future model is used, add path for that model — don't replace BGE-M3 path)
- The chunking module structure (recursive → paragraph → sentence → fixed fallback is the right hierarchy)

## Validation criteria

This ADR is validated when:

- [x] C.1 + C.2 + C.5 PRs merged (done 2026-05-18)
- [x] ICD-10 cascade benchmark ≥75% Hit Rate@3 (achieved 100%, far above gate)
- [x] icd10_codes table populated to 15,376 rows (done)
- [x] BGE_M3_TOKENIZER_PATH operator setup documented in PR #300
- [ ] Long-doc chunk-size matrix run when corpus + harness ready (deferred sprint)
- [ ] Python ingest C.3 / C.4 applied when Python ingest returns to main (conditional)

## References

- [Mimir #299](https://github.com/MegaWiz-Dev-Team/Mimir/pull/299) — Thai sentence splitter (C.1)
- [Mimir #300](https://github.com/MegaWiz-Dev-Team/Mimir/pull/300) — BGE-M3 tokenizer (C.2)
- [Mimir #301](https://github.com/MegaWiz-Dev-Team/Mimir/pull/301) — Cascade benchmark + icd10 restore (C.5)
- [Audit memory](../../../.claude/projects/-Users-mimir-Developer/memory/mimir_chunking_audit.md)
- [Solution architecture §4](../architecture/agent_rag_graph_solution_architecture.md) — 4 knowledge representations
- [Dataset inventory plan](../../../Mimir/docs/04_evaluation_and_testing/04_10_dataset_inventory_plan_2026-05-17.md) — M1 decision gates
- Sprint 48 progress: `Mimir/docs/03_implementation_plans/sprint48_progress_2026-05-07.md`
- [Sprint tracker](../sprint_tracker_2026_05_17.md) — C.1-C.6 status table
