# Funding Pitch — Thai Clinical Handwriting OCR (Domain Fine-Tune + Data Flywheel)

**Status:** plan / pitch draft · **Date:** 2026-05-30 · **Owner:** Megawiz (Asgard)
**Ask framing:** grant / R&D funding to build the root-fix recognizer that current off-the-shelf engines cannot deliver.

> Companion docs: [Medical-Document-Digitization-Platform-design.md](../architecture/Medical-Document-Digitization-Platform-design.md), [ADR-006-Syn-OCR-Stack.md](../architecture/ADR-006-Syn-OCR-Stack.md). Empirical basis: `Syn/benchmarks/results_bakeoff_vlm_2026_05_30.txt` + `results_ensemble_combos_2026_05_30.txt`.

---

## 1. The problem (one sentence)

**Automated Thai medical-insurance claims (NHSO / สปสช) are bottlenecked at a single step — reading the doctor's handwriting — and no available OCR engine, local or cloud-permitted, captures more than ~⅓ of the clinical content.**

Everything downstream of OCR in Asgard Iris already works end-to-end: entity extraction, ICD-10-TM coding, FHIR R5, NHSO XML + สปสช EDI generation. The pipeline's accuracy ceiling is the recognizer, and that ceiling is low.

## 2. Evidence (measured, not asserted)

Bake-off on **7 real doctor-handwriting pages** (de-identified clinical notes), metric = **field recall** (fraction of ground-truth clinical tokens captured — the metric that matters for claims; full-page CER is meaningless on partial-field forms):

| recognizer | token recall | speed | note |
|---|--:|--:|---|
| Apple Vision (on-device floor) | 0.222 | 1s | best single local engine |
| Typhoon-OCR-3b (q4) | 0.184 | 31s | OCR-specialized, *worse* than the floor |
| Qwen2-VL-7B general VLM | 0.207 | 66s | doesn't beat the floor as raw OCR |
| **best ensemble (AppleVision ∪ Qwen2-VL)** | **0.339** | 67s | +53% — shipped (see §6) |

**Conclusion: the recognizer is the ceiling.** Swapping or ensembling *available* engines lifts capture from 22% → 34%, but **~66% of clinical tokens are still missed.** Lexicon/KB correction can only repair the 34% already captured — it cannot recover what was never read. The only lever that moves the ceiling is **a recognizer trained on the actual data distribution: Thai clinical handwriting.**

## 3. Why this is unsolved (and why it's defensible)

- **No public dataset exists.** Thai handwriting + medical domain + real prescription/order-sheet layouts is a distribution with effectively zero open labeled data.
- **Cloud is off the table.** This is PHI on an on-prem box (one Mac mini per hospital). Cloud OCR (Gemini, Mistral, GPT-4o-vision) is banned by policy — the image cannot leave the building. So "just call a frontier VLM" is not an option even ignoring cost.
- **General models tested and insufficient.** We empirically tested a general VLM (Qwen2-VL-7B) — it reads from context but hallucinates on hard pages and does not beat the on-device floor as a raw recognizer.
- **The moat is the data, not the model.** Whoever assembles the first sizeable corpus of labeled Thai clinical handwriting owns the capability. That corpus is the fundable, defensible asset.

## 4. The solution — fine-tune fed by a self-reinforcing flywheel

**Core idea:** the human-in-the-loop review screen that Iris *already needs* (a clinician/clerk confirms the extracted diagnoses/meds before a claim is filed) **is also the annotation tool.** Every correction a reviewer makes is a free (image-region → correct-text) labeled pair. Labeling cost is amortized into normal operations — the system gets more accurate the more it is used, at zero incremental labeling budget.

```
   upload → OCR (current engine) → extract → ┌─ REVIEW (human confirms/corrects) ─┐ → claim filed
                                             │                                    │
                                             └──► (image-region, correct-text) ───┘
                                                         labeled pair
                                                            │
                                          accumulate corpus ▼
                                              periodic fine-tune ──► better recognizer ──┐
                                                            ▲                            │
                                                            └──────── deploys back ──────┘
```

**Why fine-tune, not prompt-engineer:** the failure is *perceptual* (the model cannot read the strokes), not *instructional*. Only weight updates on in-distribution data fix perception.

**Model candidates** (all keep PHI on-prem, all MLX-servable on the existing host):
- **Qwen2-VL family** (proven compatible with our MLX stack today) — LoRA/QLoRA fine-tune on the handwriting corpus.
- **TrOCR-style encoder-decoder** fine-tune (the published handwriting-OCR baseline our targets reference).
- Apple Vision is *not* fine-tunable (closed) — it stays as the deterministic floor leg of the ensemble.

## 5. Plan & milestones

| Phase | Work | Gate / success metric |
|---|---|---|
| **0. Done** | Bake-off + ensemble shipped; ceiling quantified; eval harness exists (`bench_recognizer_bakeoff.py`, field-recall) | baseline 0.222, ensemble 0.339 ✅ |
| **1. Annotation flywheel (#10)** | Build the left-image / right-text correction UI in Iris; persist (region, text) pairs to a labeling store; instrument capture rate | UI live; ≥N corrected pages/week flowing |
| **2. Corpus** | Accumulate labeled pages from live HITL use across pilot hospital(s); de-dup, QA, hold-out split | target corpus size (e.g. 2–5k labeled pages) |
| **3. Fine-tune v1** | LoRA fine-tune candidate model on corpus; eval on held-out real pages via the existing harness | **token recall 0.34 → ≥0.60** |
| **4. Close the loop** | Deploy fine-tuned model as the ensemble's VLM leg; measure flywheel acceleration (recall vs corpus size curve) | recall improves with each retrain cycle |

**Success metric is already operationalized** — the same `field recall` number in §2, on a held-out set of real pages. No new metric to invent; progress is measurable from day 1.

## 6. What's already built (de-risks the ask)

This is not a cold start. Funded or not, the surrounding system is production-grade:
- ✅ Full claims pipeline (upload → OCR → extract → ICD-10-TM → FHIR R5 → NHSO XML / สปสช EDI) working E2E.
- ✅ **Ensemble recognizer shipped today** (`applevision+vlm` engine in Syn; permanent Qwen2-VL MLX service) — +53% capture *now*, while the fine-tune corpus accumulates.
- ✅ Confidence-gate + HITL review already in the product (the flywheel's data source is live).
- ✅ Reproducible eval harness on real data.
- ✅ On-prem, PHI-safe architecture (single tenant per Mac mini); AGPL-3.0 + commercial dual license.

**The grant funds exactly one thing: turning the existing HITL stream into a labeled corpus and the corpus into a recognizer that breaks the 66%-miss ceiling.**

## 7. Budget shape (to size for the application)

| Line | Rationale |
|---|---|
| Annotation-UI engineering (#10) | one-time build of the flywheel capture surface |
| Training compute | LoRA fine-tunes are modest; Mac-mini MLX local + occasional cloud GPU burst for larger runs (no PHI in synthetic/augmented pretraining) |
| Data QA / curation | light human QA on the auto-captured corpus |
| Eval & iteration | recall-curve experiments across retrain cycles |

*(Fill in figures per the funding body's template; the work decomposes cleanly into the four phases above.)*

## 8. Risks & honest caveats

- **Flywheel cold-start:** until the corpus is large enough, accuracy gains are slow. Mitigation: the shipped ensemble (+53%) carries the product in the interim; data augmentation / synthetic Thai handwriting can warm-start phase 3.
- **Latency:** the VLM leg is ~67s/page. Acceptable for HITL batch claims (not real-time); a fine-tuned smaller model should be faster than the general 7B.
- **Corpus generalization:** one hospital's handwriting ≠ all hospitals'. Mitigation: multi-site pilot; the flywheel naturally diversifies as deployment grows.
- **Ground-truth quality:** HITL corrections are confirmations of *extracted entities*, not full transcriptions — phase 1 must capture region-level text, not just final entity edits, to be useful training data.
