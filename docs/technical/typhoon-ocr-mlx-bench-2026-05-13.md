# Typhoon-OCR MLX Bench — 2026-05-13

> Self-converted MLX quants of `typhoon-ai/typhoon-ocr-{3b,7b}` benchmarked
> against Ollama on Apple Silicon. All four MLX variants published under
> [MegawizCo](https://huggingface.co/MegawizCo).

## TL;DR

- **Best throughput-default:** `MegawizCo/typhoon-ocr-3b-mlx-q4` — 107 TPS, 3.5 GB peak, CER median 0.009 on synthetic handwriting
- **Best CER ceiling:** `MegawizCo/typhoon-ocr-7b-mlx-q8` — CER max 0.028 (3× lower worst-case vs 3b q8), pay 32 TPS / 9 GB
- **Switch from Ollama to MLX = +33% wall-clock speedup on 3b**, ~half RAM
- ADR-006's "blocked on mlx-vlm Typhoon vision-tower support" is **no longer true**. `mlx-vlm 0.5.0` works for 3b out-of-box; 7b needs a config-only patch (see Reproduce section).

## Setup

| Component | Detail |
|---|---|
| Hardware | Mac mini, Apple Silicon, 24 GB unified memory |
| Date | 2026-05-13 |
| `mlx-vlm` | 0.5.0 |
| Ollama | latest at time of run |
| Test set | 2 synthetic printed + 5 synthetic handwriting (Syn benchmarks/data/) |
| Ground truth | Syn/benchmarks/ground_truth*.json |
| Prompt | `Extract all text from this image.` |
| Output parser | `{"text": "..."}` (3b) OR `{"natural_text": "..."}` (7b), fallback to regex |

Synthetic disclaimer: the test images are rendered Thai medical text in
handwriting-style fonts, not real photographed handwriting. Real-world CER
expected to be higher; partner-hospital eval is the B-50h.1 path.

## Per-engine summary

| Backend | Disk | HW CER median | HW CER max | Wall median | TPS | Peak RAM |
|---|---|---|---|---|---|---|
| MLX 3b q4 | 2.9 GB | 0.009 | 0.081 | 1.95 s | 107 | 3.5 GB |
| MLX 3b q8 | 4.3 GB | 0.000 | 0.081 | 2.34 s | 65 | 5 GB |
| Ollama 1.5-3b Q4 | 2.0 GB | 0.000 | 0.058 | 2.90 s | 78 (40-84) | 4 GB |
| MLX 7b q4 | 5.3 GB | 0.012 | 0.037 | 3.55 s | 56 | 6 GB |
| MLX 7b q8 | 8.8 GB | 0.012 | 0.028 | 4.66 s | 32 | 9 GB |
| Ollama 7b | 15 GB GGUF | — | — | — | — | 15+ GB load → swap thrash, skipped |

Synthetic-printed CER was 0.000 for every backend; differentiation only
visible on the 5-image handwriting set.

## Per-image, per-backend detail (handwriting set)

| Image | MLX 3b q4 | MLX 3b q8 | Ollama 1.5-3b | MLX 7b q4 | MLX 7b q8 |
|---|---|---|---|---|---|
| hw-rx-01 | 0.000 | 0.000 | 0.000 | 0.008 | 0.008 |
| hw-rx-02 | 0.009 | 0.000 | 0.018 | 0.000 | 0.000 |
| hw-rx-03 | 0.000 | 0.000 | 0.000 | 0.037 | 0.028 |
| hw-note-01 | 0.010 | 0.010 | 0.000 | 0.020 | 0.020 |
| hw-lab-01 | 0.081 | 0.081 | 0.058 | 0.012 | 0.012 |

Notes:

- **hw-lab-01 (the lab-values image) is the ceiling case.** 3b family caps
  at 0.081, 7b cuts that to 0.012 — 7b is more robust at numeric/character
  disambiguation (e.g., `1.1` vs `l.l`, `0` vs `O`).
- **hw-rx-03 is unexpectedly hard on 7b** (0.037 / 0.028) but easy on 3b
  (0.000). Possible cause: 7b sees longer dependencies between cursive
  letters and over-generalises. Worth re-checking on a real-photo version.
- **MLX vs Ollama on 3b:** the 1.5-3b Ollama variant is a different fine-tune
  base from `typhoon-ocr-3b`, so this isn't a pure quant comparison. Take
  the comparison as "current Asgard production (Ollama 1.5-3b) vs proposed
  MLX path (typhoon-ocr-3b)", not "same model, two runtimes".

## What changed in the cluster

Nothing yet. The MLX variants are uploaded but Asgard's Syn smart router
still has `SYN_TYPHOON_URL = http://host.orb.internal:11434/v1`. Switching
to MLX is a Sprint 51 P1 follow-up (originally a P2 in
[sprint-planning.md](../sprint-planning.md), now demoted blocker — ADR-006
unblocked):

1. Wire Heimdall MLX endpoint as an additional Typhoon target
2. A/B flag in syn-api smart router (`SYN_TYPHOON_BACKEND=mlx|ollama`)
3. Burn-in for 1 sprint on staging
4. Cut over default

## Reproduce — 3b conversion

```bash
uv pip install mlx-vlm
mlx_vlm.convert --hf-path typhoon-ai/typhoon-ocr-3b -q --q-bits 4 \
  --mlx-path typhoon-ocr-3b-mlx-q4
mlx_vlm.convert --hf-path typhoon-ai/typhoon-ocr-3b -q --q-bits 8 \
  --mlx-path typhoon-ocr-3b-mlx-q8
```

Quantization yields:
- q4 → 2.9 GB on disk, 6.549 effective bits/weight
- q8 → 4.3 GB on disk, 9.836 effective bits/weight

Vision-projector + layer-norm weights stay full precision per mlx-vlm
defaults — that's why "q4" is ~6.5 bits/weight not 4.0.

## Reproduce — 7b conversion (with config patch)

The upstream `typhoon-ai/typhoon-ocr-7b` config.json **omits** the
`vision_config` fields that `mlx-vlm`'s Qwen2.5-VL loader requires. Without
them, mlx-vlm falls back to 3b's defaults → shape mismatch at the
vision-tower merger MLP (`Expected (1536, 5120) but received (3584, 5120)`).

Fix: copy the missing fields from upstream `Qwen/Qwen2.5-VL-7B-Instruct`
(vision tower is identical, the upstream serialization just dropped them).

```bash
# 1. Pull upstream into HF cache
mlx_vlm.convert --hf-path typhoon-ai/typhoon-ocr-7b -q --q-bits 4 \
  --mlx-path probe 2>&1 || true  # expected to fail — populates cache

# 2. Build a local dir that symlinks weights + has a patched config
CACHE=$(find ~/.cache/huggingface/hub/models--typhoon-ai--typhoon-ocr-7b/snapshots \
  -mindepth 1 -maxdepth 1 -type d | head -1)
mkdir typhoon-ocr-7b-patched
for f in "$CACHE"/*; do
  ln -sf "$(readlink -f "$f")" "typhoon-ocr-7b-patched/$(basename "$f")"
done
rm typhoon-ocr-7b-patched/config.json
python3 -c "
import json
with open('$CACHE/config.json') as f: cfg = json.load(f)
cfg['vision_config'].update({
    'depth': 32, 'hidden_act': 'silu', 'hidden_size': 1280,
    'intermediate_size': 3420, 'num_heads': 16, 'in_chans': 3,
    'out_hidden_size': 3584, 'patch_size': 14, 'spatial_merge_size': 2,
    'spatial_patch_size': 14, 'window_size': 112,
    'fullatt_block_indexes': [7, 15, 23, 31],
    'tokens_per_second': 2, 'temporal_patch_size': 2,
})
with open('typhoon-ocr-7b-patched/config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
"

# 3. Convert from the patched local dir
mlx_vlm.convert --hf-path ./typhoon-ocr-7b-patched -q --q-bits 4 \
  --mlx-path typhoon-ocr-7b-mlx-q4
mlx_vlm.convert --hf-path ./typhoon-ocr-7b-patched -q --q-bits 8 \
  --mlx-path typhoon-ocr-7b-mlx-q8
```

Quantization yields:
- 7b q4 → 5.3 GB on disk, 5.439 effective bits/weight
- 7b q8 → 8.8 GB on disk, 9.112 effective bits/weight

The patched config.json ships with the published HF repos so downstream
users don't have to re-patch.

## Output format quirk — 3b vs 7b

```jsonc
// 3b output
{"text": "ใบสั่งยา\nผู้ป่วย: นายสมชาย ใจดี\n..."}

// 7b output (note key change)
{"natural_text": "ใบสั่งยา\nผู้ป่วย: นายสมชาย ใจดี\n..."}
```

`Bifrost/src/swarm_engine/skills.rs::OcrExtractTool` calls syn-api which
calls the engine; the JSON unwrapping happens upstream of the agent so
Bifrost code is unaffected. But anyone calling these models direct from
Python needs to handle both keys.

## Why not Ollama 7b in the bench?

Ollama keeps the model resident with `keep_alive`. Loading 7b on a 24 GB
Mac mini took the system to **31.7 GB / 32.7 GB swap (97 %)** during our
first run — bench script got SIGTERM-ed mid-run. MLX's tighter memory
footprint (6 GB peak for q4, 9 GB peak for q8 — both under 10 GB) sidesteps
this; that's the bigger story than the speedup numbers above.

Real fix path if we want Ollama 7b comparison: configure Ollama with a
smaller context window (`OLLAMA_NUM_CTX`), or use `llama-server` directly
without the Ollama keep-alive daemon. Logged as a Sprint 51 stretch task.

## Published artifacts

| Path | Notes |
|---|---|
| `MegawizCo/typhoon-ocr-3b-mlx-q4` | throughput-default, our recommended production engine |
| `MegawizCo/typhoon-ocr-3b-mlx-q8` | 3b high-fidelity |
| `MegawizCo/typhoon-ocr-7b-mlx-q4` | 7b throughput |
| `MegawizCo/typhoon-ocr-7b-mlx-q8` | lowest CER ceiling on the synthetic set |

All four inherit Apache 2.0 from `typhoon-ai/typhoon-ocr-{3b,7b}`. Each
README documents bench numbers + the conversion command + (for 7b) the
config patch.

## Sprint 51 follow-up

- [x] Wire Heimdall MLX endpoint for Typhoon (env-var swap path) — done 2026-05-13, Heimdall PR #9
- [x] A/B flag in syn-api smart router for `SYN_TYPHOON_BACKEND` — done via env vars, Syn PR #13
- [ ] Re-bench on real photographed handwriting once B-50h.1 partner-hospital flow ships any samples
- [ ] Try `llama-server` direct (skip Ollama daemon) for 7b GGUF comparison
- [ ] Re-confirm `hw-rx-03` regression on 7b — might be a sampling artifact

---

## Sprint 51 reality check — real Thai medical certs (2026-05-13)

**The synthetic-only numbers above lied by omission.** Once we benched the
same engines on 10 real photographed Thai medical certificates (`Syn/data/images/T0{01..10}`,
ground-truth in `Syn/data/TestimageRawText.csv`), the gap to "production ready"
became obvious.

### Path tested

```
client → Heimdall :8080 (auth + router) → either VLM (:8082/:8083)
                                       or Google Gemini OpenAI-compat
```

Same endpoint Asgard agents call. Same prompt + envelope as Syn's
`call_openai_chat_ocr`.

### Run A — generic "extract all text" prompt

| Engine | n | CER median | CER mean | CER max | Wall median |
|---|---|---|---|---|---|
| MLX 3b q4 | 10 | 5.329 | 12.538 | **45.710** | 11.1 s |
| MLX 3b q8 | 10 | 4.955 | 10.038 | **62.452** | 8.2 s |
| Gemini 3 Flash | 10 | 3.805 | 5.214 | **12.875** | 21.4 s |
| Gemini 3.1 Pro | 10 | 10.178 | 30.214 | **123.253** | 104.3 s |

CER >> 1 everywhere — the **extracted text was multiple times the size of
ground truth**. Two reasons:
1. **Ground-truth mismatch.** The CSV holds only content fields (patient
   name, doctor name, HN, license, diagnosis, comment). Every model
   correctly extracts the *whole image* including hospital headers,
   addresses, watermarks, signatures — which the GT doesn't include.
2. **Runaway generation on MLX.** Four of the MLX runs hit
   `max_tokens=4096` (T001 q4, T005 q4/q8, T009 q4, T010 q8) — model
   spirals into describing the form template instead of stopping.
   Gemini doesn't show this; Pro instead generates very thorough,
   over-complete extractions.

### Run B — field-targeted prompt (Option D fix)

Switched to a system prompt that explicitly enumerates the expected
fields and says "do NOT include hospital name, address, watermarks,
signatures, form numbers". Same 10 images, same engines.

| Engine | n | CER median | CER mean | CER max | Wall median |
|---|---|---|---|---|---|
| MLX 3b q4 | 10 | 4.941 | 14.579 | 83.194 | 10.3 s |
| MLX 3b q8 | 10 | 5.114 | 11.783 | 44.978 | 13.2 s |
| **Gemini 3 Flash** | 10 | **0.432** | **0.539** | **1.495** | 23.7 s |
| Gemini 3.1 Pro | 10 | 0.303 | 11.770 | 113.750 (T002 outlier) | 31.6 s |

**Field-targeted prompt collapses Flash's CER from 3.8 → 0.4 (8× better).**
Same prompt has near-zero effect on MLX — the 3b VLM doesn't follow the
"do not include the hospital header" instruction; output is still ~5×
ground-truth length on most cases. That's a model-capacity / instruction-
following limit, not a quantization issue (q8 doesn't help either).

Pro's median is even better (0.303) but one outlier (T002 = 113.750)
breaks the mean — Pro emitted 10,044 characters for an 88-char ground
truth. Likely included internal reasoning in the output stream. Pro
needs a length cap or response post-filter to be usable as a Curator
escalation tier.

### Production recommendation (revised)

| Tier | Engine | Use case | Latency | Cost / page |
|---|---|---|---|---|
| **Tier 1 — default** | Gemini 3 Flash + field prompt | Real Thai medical certs | ~24 s | ~$0.0001 |
| Tier 2 — escalation | Gemini 3.1 Pro + length cap | Curator-flagged hard cases | ~30 s | ~$0.05 |
| Tier 0 — PHI-strict | MLX 3b q4 + body-region crop | Tenants with `ocr_phi_strict=true` | ~10 s | $0 (local) |

The MLX tier needs help to be production-ready on real photographed
certs:
- Pre-processing: crop the body region (between header and footer) so
  the model can't see hospital identity headers.
- Or: post-process the response to strip everything before "Patient
  Name:" and after "Doctor Comment:" / signature blocks.
- Or: route MLX-extracted text through a second LLM call ("keep only
  the patient/doctor/HN/diagnosis/comment fields") — adds latency but
  bridges the quality gap.

### Open follow-ups

- [ ] **Length cap heuristic** in syn-api smart router — kill any
      response > 3× ground-truth template length, fall back to Flash.
- [ ] **Body-region crop pre-processor** — likely the highest-leverage
      win for the MLX tier.
- [ ] **Fine-tune Typhoon-OCR-3b on field-extraction format** — Sprint
      55-57 candidate alongside the Thai medical NER plan.
- [ ] **Real-photo eval set expansion** — n=10 is too small to draw
      strong conclusions. Aim for 50-100 once B-50h.1 partner-hospital
      flow is live.
- [ ] **Ground-truth definition fix** — CSV currently holds content-only.
      Either re-transcribe to "all visible text" OR add a separate
      field-only metric. Both are useful; the content-only one is the
      one Asgard's downstream pipelines actually care about.
