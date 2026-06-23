# Tier A — Public Handwriting Annotation Hub (spec)

**Status:** design, updated 2026-06-04 · **Scope:** consensus-annotation hub for the handwriting fine-tune flywheel.
**Goal:** transcribe Thai clinical handwriting, aggregate by **consensus** into a golden dataset that bootstraps the recognizer fine-tune (long-term OCR plan, Stage 1).

> **DECISION 2026-06-04 — start on REAL consented docs via the GOVERNED pool.** Consent has been obtained, scoped to **research/training/annotation** (NOT public display). Therefore the real docs go through the **governed** access model — vetted, registered annotators under DUA, reachable over **Tailscale** (annotators already on the tailnet), data on-prem, **Tyr-audited**, minimum-necessary (annotate handwriting **region crops**, not full charts). This is the Tier-B access model, *unlocked now by consent* — it gives real-distribution data without open-internet exposure. The open/public + synthetic track (below) becomes a **later, optional** volume booster, NOT the starting point. The **consensus engine (§4) is identical** for both; only the access/governance layer differs.

---

## 0. Hard boundary (why Tier A exists)
Real clinical handwriting is PHI → **cannot** go on a public cloud / open-internet annotation (PDPA sensitive data; `syn_data_internal_only`; can't reliably de-identify handwriting). Tier A therefore uses **only publishable, non-PHI data**. It bootstraps + proves the consensus mechanism; the real-distribution golden set comes from **Tier B** (vetted clinicians, DUA/IRB, on-prem/DPA, Tyr-audited).

## 1. Data (⚠️ does not exist yet — step 0 is to create it)
Syn/data today is all real PHI. Tier A needs a **publishable corpus**:
1. **Synthetic Thai clinical handwriting** — generate from: handwriting fonts + clinical-phrase templates (drug orders, dx, progress notes), optionally a handwriting GAN/diffusion. Each item: a line/region image + the known generated string (so synthetic items double as **honeypots** with known answers).
2. **Consented-donated handwriting** — real handwriting donated WITH consent + provenance, scrubbed of identifiers (no names/HN/dates). Closer to real distribution than pure synthetic.
Store provenance + license + (synthetic|donated) flag per item. NO PHI ever.

## 2. Reuse (don't rebuild)
- **Annotation UI**: extend the existing OCR-GT annotation UI (v2.3.11, `/syn-ocr/annotation`, multi-user + progress) — verify its schema, add the consensus layer. Fallback: Label Studio (`Syn/benchmarks/region_annotation/`, TextArea-per-box config).
- **Pre-annotation**: applevision line-bbox (already in the extract response) pre-draws line boxes → annotators transcribe per line, don't crop from scratch.
- **Output → eval**: feed the Mimir eval gold-sets harness; metric = token/field recall (not CER).

## 3. Annotation task
Per item = one handwriting **line/region image**. Annotator types what it reads (verbatim transcription). Optional: flag illegible / not-handwriting / contains-identifier (→ quarantine). Medical-staff track tagged (higher trust weight, §4).

## 4. Consensus → golden (the core mechanism)
Each item annotated independently by **K annotators** (target K≥3, escalate ties).

- **Agreement metric:** normalized transcription (lowercase, strip whitespace/punct) → cluster identical strings; agreement = size of largest cluster / total. Use normalized edit-distance for near-matches (merge clusters within edit-dist ≤ τ).
- **Accept as golden when:** largest-cluster size ≥ `MIN_AGREE` (e.g. 3) AND agreement ≥ `AGREE_THRESHOLD` (e.g. 0.67) → that string = golden label, with `confidence = agreement`, `n_annotators`.
- **Escalate when:** no cluster reaches threshold after K → route to **expert (clinician) tie-break**; their answer is authoritative.
- **Annotator reliability (weighted vote):** seed **honeypots** (synthetic items with known answer) ~10-15% of each annotator's queue → compute per-annotator accuracy → `reliability ∈ [0,1]`. Votes weighted by reliability × track-weight (medical-staff > general). Down-weight/flag annotators below a floor (anti-abuse).
- **Stats persisted per item:** n_annotators, agreement, accepted label, confidence, status (open|golden|escalated|quarantined). Per annotator: items done, honeypot accuracy, reliability.

## 5. Quality / anti-abuse
- Honeypots (known-answer synthetic) interleaved → reliability + spam detection.
- Min time-per-item, duplicate-submission guard, no self-consensus (K distinct annotators).
- Identifier-flag → quarantine (defense even though data is non-PHI by construction).
- Golden set is **frozen + versioned**; an item never trains AND evals (keep a held-out eval split, clinician-signed).

## 6. Output → fine-tune flywheel
Golden items = `(image, region bbox, transcription, confidence, n_annotators, source)` → the handwriting recognizer fine-tune corpus (long-term plan Stage 2). Tier A supplies the **bootstrap + synthetic volume**; Tier B supplies real-distribution golden later. Honest gap: synthetic distribution ≠ real clinical handwriting → Tier A lifts the recognizer off zero but the real ceiling-move needs Tier B data.

## 7. Engagement (volume)
Leaderboard, contribution count, accuracy badge; medical-staff verified track (trust weight + recognition). Keep it opt-in, transparent that contributions train an open medical-OCR model.

## 8. Build order
1. **Data gen** — synthetic Thai clinical handwriting generator (+ honeypots). ← prerequisite, nothing works without it.
2. **Consensus service** — aggregation + reliability + golden-promotion (the novel core). DB: items, annotations, annotators, golden.
3. **Hub UI** — extend `/syn-ocr/annotation` (or Label Studio) with line-transcription + consensus status.
4. **Export** — golden → fine-tune corpus + Mimir eval gold-set.

**Recommended first build:** step 1 (synthetic generator + honeypots) + step 2 (consensus schema + promotion logic) — these are the parts with no existing equivalent; the UI can lean on what exists.
