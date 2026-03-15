---
name: performance-benchmark
description: "Benchmark LLM inference, RAG pipeline, and API performance on Apple Silicon and NVIDIA. Report generation, regression detection, and optimization."
---

# Performance Benchmark

> "If you don't measure it, you can't improve it."

## Purpose

Systematically benchmark Asgard components — LLM inference (Heimdall), RAG pipeline (Mimir), and API services — to track performance, detect regressions, and optimize for Apple Silicon / NVIDIA hardware.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | Component data flows |
| Heimdall `benchmark_results/` | Existing benchmark data |
| Heimdall `docs/iso_29110/test_report.md` | Previous benchmark reports |

---

## Process

### 1️⃣ LLM Inference Benchmarking (Heimdall)

**Key Metrics:**
| Metric | Definition | Target |
|--------|-----------|--------|
| Tokens/second | Generation throughput | Model-dependent |
| TTFT | Time to first token | < 500ms |
| Latency (P50/P95/P99) | Response time distribution | Track trend |
| Memory Usage | Peak VRAM/unified memory | Within hardware limit |

**Methodology:**
```bash
# Standard test prompts (reproducible)
# Prompt categories:
# - Short (< 50 tokens): Quick Q&A
# - Medium (100-500 tokens): Summarization
# - Long (500+ tokens): Analysis/Generation

# Variables to control:
# - Model (Qwen3.5-9B, Qwen3.5-27B, MedGemma)
# - Quantization (F16, Q8, Q4)
# - Backend (MLX, llama.cpp, Ollama, vLLM)
# - Hardware (M4 16GB, M4 Pro 36GB, NVIDIA)
# - Concurrency (1, 5, 10 users)
```

### 2️⃣ RAG Pipeline Benchmarking (Mimir)

**Stages to benchmark:**
```
Document → Chunk → Embed → Index → Query → Retrieve → Generate

Timing each stage:
┌─────────────┬──────────┐
│ Stage        │ Target   │
├─────────────┼──────────┤
│ Chunking     │ < 1s/doc │
│ Embedding    │ < 100ms  │
│ Indexing     │ < 50ms   │
│ Retrieval    │ < 200ms  │
│ Generation   │ < 5s     │
│ E2E (query)  │ < 8s     │
└─────────────┴──────────┘
```

**Quality Metrics:**
- Retrieval recall @ K (relevant chunks in top-K)
- Answer relevance score
- Faithfulness (grounded in retrieved context)

### 3️⃣ API Load Testing

```bash
# Using wrk for HTTP benchmarks
wrk -t4 -c100 -d30s http://localhost:8000/health

# Using k6 for scenario-based testing
# k6 script example:
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },  // Ramp up
    { duration: '1m', target: 20 },    // Steady
    { duration: '10s', target: 0 },    // Ramp down
  ],
};

export default function () {
  const res = http.get('http://localhost:3100/health');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
```

### 4️⃣ Hardware-Specific Optimization

| Hardware | Optimize For |
|----------|-------------|
| Apple Silicon (M4) | Unified memory bandwidth, MLX batch size |
| Apple Silicon (M4 Pro/Ultra) | Multi-model concurrency, memory pressure |
| NVIDIA (DGX) | CUDA utilization, vLLM tensor parallelism |

### 5️⃣ Benchmark Report Template

```markdown
# Benchmark Report — [Date]

## Hardware
- Device: [Mac Mini M4 Pro 36GB]
- OS: [macOS 15.x]
- Backend: [MLX / llama.cpp / vLLM]

## Model: [Qwen3.5-9B-Q8]

### Inference Performance
| Metric | Value | Previous | Δ |
|--------|-------|----------|---|
| Tokens/sec | 45.2 | 43.1 | +4.9% |
| TTFT | 320ms | 340ms | -5.9% |
| P95 Latency | 2.1s | 2.3s | -8.7% |
| Peak Memory | 12.8GB | 12.8GB | 0% |

### RAG Pipeline
| Stage | P50 | P95 |
|-------|-----|-----|
| ... | ... | ... |

## Regression Analysis
[Any performance degradation > 10% flagged]

## Recommendations
[Optimization suggestions]
```

### 6️⃣ Regression Detection

- **Threshold**: Flag if any metric degrades > 10% vs previous run
- **Automation**: Save results as JSON for trend tracking
- **Storage**: `benchmark_results/YYYY-MM-DD_model_hardware.json`

---

## Key Principles
- Same hardware, same conditions for every benchmark run
- Warm up the model before measuring (discard first 3 runs)
- Report P50, P95, P99 — averages hide outliers
- Compare against your own baselines, not internet numbers

## When to Use
After upgrading models, changing quantization, modifying pipeline stages, before releases, or quarterly performance review.
