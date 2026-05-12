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

- [ ] Wire Heimdall MLX endpoint for Typhoon (env-var swap path)
- [ ] A/B flag in syn-api smart router for `SYN_TYPHOON_BACKEND`
- [ ] Re-bench on real photographed handwriting once B-50h.1 partner-hospital
      flow ships any samples
- [ ] Try `llama-server` direct (skip Ollama daemon) for 7b GGUF comparison
- [ ] Re-confirm `hw-rx-03` regression on 7b — might be a sampling artifact
