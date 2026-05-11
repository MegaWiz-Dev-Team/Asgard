# ADR-006 — Syn S1 OCR Stack: 3-tier hybrid (PaddleOCR + Typhoon-OCR + Gemini Flash + Pro)

**Status:** Accepted (revised 2026-05-08 per B-50a.2)
**Date:** 2026-05-08 (initial) / 2026-05-08 (revision)
**Sprint:** 50 (Syn S1 — OCR Foundation)
**Related ADRs:** ADR-007 (Skuggi PII Guardrail) — gates the cloud tiers below.

## Revision summary (B-50a.2)

The original 4-tier decision included a `chandra-local` Tier 1a for handwriting on the assumption it was a lightweight (~80MB) EasyOCR-class engine. When `chandra-ocr` v0.2.0 actually shipped in 2026-05, it turned out to be a **10.6 GB VLM** on Qwen3.5-VL — same weight class as Tier 1c Typhoon-OCR.

Bench (B-50a.2, 5 synthetic Thai handwritten clinical notes):

| Engine | CER median | Latency median |
|---|---|---|
| `chandra-local` (EasyOCR-paragraph 1.7.2) | 0.193 | 8.2 s |
| `typhoon-ocr-local` (1.5-3B via Ollama)   | **0.000** | **2.9 s** |

Typhoon dominates by a wide margin. Conclusion: **collapse 4-tier → 3-tier**, drop the `chandra-local` Tier 1a entirely, reroute `doc_type=handwriting` to Typhoon. Full assessment + bench in [Syn/docs/B-50a.2_chandra_assessment_2026-05-08.md](https://github.com/MegaWiz-Dev-Team/Syn/blob/main/docs/B-50a.2_chandra_assessment_2026-05-08.md).

## Context

Sprint 50 introduces 👁️ Syn (Norse goddess of vigilance), Asgard's TOR
(Tools of Recognition) sub-system for visual document processing. S1
focuses on OCR for Thai medical documents — patient intake forms, lab
reports, prescriptions, hospital HRMS forms. Mega-Care synergy is direct
(patient intake automation).

Document types span:
- Thai stock print (forms, IDs, lab outputs)
- Handwritten doctor notes
- Complex tables (lab results)
- Mixed-language (Thai + English medical terms)
- High-stakes documents (legal, insurance, critical lab)

A single OCR engine cannot cover all four well at the price/quality
points needed.

## Decision

**3-tier hybrid stack with local-first default + opt-in cloud premium.**

| Tier | Engine | License | Cost | Use case |
|:---:|---|---|---|---|
| **1b** | `PaddleOCR` PP-OCRv4 (~50k ⭐) | Apache 2.0 | $0 (local) | Thai stock print, forms, fast latency |
| **1c** | `Typhoon-OCR 1.5-3B` (Ollama-local VLM) | Apache 2.0 | $0 (local) | Handwriting, complex tables, mixed-language, quality-uncertain |
| **2** | `gemini-3-flash` | proprietary API | ~$0.001-0.005 / page | Multilingual fallback when local confidence low |
| **3** | `gemini-3.1-pro` | proprietary API | ~$0.05-0.20 / page | High-stakes (legal, critical lab, complex layouts) |

**Smart router** (rule-based, evaluated in order, first match wins):

1. PHI-strict tenant flag set → LOCAL only (Tier 1b / 1c)
2. Per-call `--engine` override → that engine
3. Document type known: `handwriting / complex_table` → 1c Typhoon; `form / thai_print` → 1b PaddleOCR
4. Document size >5p OR marked "critical"/"legal" → Tier 3 (Pro) IF tenant `cloud_pro_enabled` else Tier 2 (Flash) else 1c best-effort
5. Local engine confidence <0.70 → Tier 2 (Flash) IF `cloud_flash_enabled` else local + warn
6. Default → 1b PaddleOCR → fallback 1c Typhoon

**Note on tier numbering:** the legacy `1a` slot (chandra-local) is retired and not reissued — `1b` / `1c` keep their numbers for audit-log + dashboard continuity. New engines added in future sprints get `1d`, `1e`, etc.

## Options considered

### A. Full local stack only (chandra + PaddleOCR)
- ✅ $0 ongoing cost · 100% PDPA-clean
- ❌ Caps quality at "good local OCR" — handwriting/Thai-mixed-English struggles documented; no escalation path for hard cases
- **Rejected:** quality ceiling too low for clinical workflows; no graceful degradation for edge cases

### B. Cloud-first (Gemini Pro for everything)
- ✅ Best quality
- ❌ Per-page cost (~$0.20) makes patient-volume unsustainable; PDPA blocker (PHI to Google)
- **Rejected:** cost + privacy blockers; defeats Asgard's local-first pitch

### C. surya / marker (datalab-to, GPL-3.0)
- ✅ Strong quality, 19.7k + 34.8k stars
- ❌ **GPL-3.0 viral clause conflicts with Asgard Commercial Enterprise tier** — Enterprise customers embedding Asgard would be forced to GPL their entire product, destroying the commercial moat ([med_open_claw_initiative.md memory](../../../.claude/projects/-Users-mimir-Developer/memory/med_open_claw_initiative.md))
- **Rejected:** license conflict with open-core business model
- **Future:** revisit if Datalab offers commercial license at acceptable margin

### D. Microsoft TrOCR / Tesseract
- ✅ Mature, free
- ❌ TrOCR Apache 2.0 but heavy GPU footprint; Tesseract Apache 2.0 but Thai accuracy noticeably worse than PaddleOCR PP-OCRv4
- **Rejected:** weaker Thai support

### E. **4-tier hybrid (originally chosen, superseded)**
- ✅ Local-first default (covers ~85% of routine docs at $0)
- ✅ Opt-in cloud for the 15% hard cases (controlled cost)
- ✅ All-Apache-2.0 local stack preserves Commercial moat
- ✅ Cloud tier reuses existing Heimdall step-up router pattern (Sprint 36)
- 🟡 Two services to maintain locally (chandra + PaddleOCR); router complexity
- 🟡 chandra is newer (~1 yr); accept as monitored risk
- **Superseded by F** after B-50a.2 bench showed Typhoon-OCR Tier 1c outperforms chandra-local on handwriting (CER 0.000 vs 0.193).

### F. **3-tier hybrid (CHOSEN, current)**
- ✅ Same local-first / cloud-opt-in shape as E
- ✅ One fewer local service to maintain (drop chandra-sidecar)
- ✅ Typhoon-OCR (already deployed for B-50a.3) absorbs the handwriting/quality-uncertain workload at higher accuracy AND lower latency than chandra-local would have provided
- ✅ Removes "two adjacent VLMs at Tier 1a + Tier 1c doing similar work" smell
- 🟡 Single-engine handwriting risk — if Typhoon regresses, no second-opinion local engine. Mitigation: B-50h benchmark (real Thai handwriting from clinician partner) + Tier 2 Flash escalation on confidence drop.

## Consequences

### Positive
- **Commercial Enterprise tier protected** — no GPL viral clause exposure
- **PDPA defensible** — default local; cloud requires explicit per-tenant opt-in + Skuggi (ADR-007) PII redaction
- **Cost predictable** — small clinic ~$0-25/mo, hospital ~$50-150/mo, specialty up to $200/mo
- **Reusable pattern** — same Heimdall step-up route works for Sprint 52 Sága (STT) and Sprint 53 vision LLM

### Negative
- **2 local services to maintain** — PaddleOCR + Typhoon-OCR drift, version pinning, ops (one fewer than 4-tier — chandra retired)
- **Router complexity** — rule-based v0 may need ML-based v1 (deferred)
- **Single handwriting engine** — Typhoon-OCR is the only local option for handwriting. If it regresses, no local fallback. Mitigation: confidence-gated cloud Flash escalation (rule 5) + quarterly bench.

### Mitigations
- B-50h test set: 30 Thai docs (10 print, 10 handwriting, 10 table) × 3 engines = 90-cell benchmark grid before sprint close
- B-50l tenant settings include `pii_mode` (chained to ADR-007 Skuggi) before any cloud call goes live
- B-50m cost guard middleware enforces monthly per-tenant cap
- Quarterly stack review: if Typhoon Thai accuracy regresses → re-evaluate adding back a handwriting-specific engine (e.g. mature chandra-ocr-2 with multistage Dockerfile if image size mitigations are workable)

## Future revisits

- **2026-Q3:** revisit chandra-ocr-2 if (a) image size mitigations land (multistage Dockerfile, model on shared volume) AND (b) bench shows chandra beats Typhoon on a specific document class. Until then, Tier 1a stays retired.
- **2026-Q4:** if Sprint 52 Sága needs reversible PII (voice context) → upgrade Skuggi v1 with HSM keys
- **2027:** if Asgard Commercial moat sufficiently established + Datalab commercial pricing reasonable → re-evaluate surya/marker

## References

- Sprint 50 backlog: [`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md) Sprint 50 section
- ADR-007 Skuggi (gates cloud tiers): [`ADR-007-Skuggi-PII-Guardrail.md`](ADR-007-Skuggi-PII-Guardrail.md)
- B-50a.2 chandra integration assessment + bench: [`Syn/docs/B-50a.2_chandra_assessment_2026-05-08.md`](https://github.com/MegaWiz-Dev-Team/Syn/blob/main/docs/B-50a.2_chandra_assessment_2026-05-08.md)
- Typhoon-OCR: https://github.com/scb-10x/typhoon-ocr (Apache 2.0)
- PaddleOCR: https://github.com/PaddlePaddle/PaddleOCR (Apache 2.0)
- chandra (retired Tier 1a): https://github.com/datalab-to/chandra (Apache 2.0)
- Asgard roadmap (Syn → Sága → Visual BMI sequence): [`../strategy/roadmap.md`](../strategy/roadmap.md)
