# ADR-006 — Syn S1 OCR Stack: 4-tier hybrid (chandra + PaddleOCR + Gemini Flash + Pro)

**Status:** Accepted
**Date:** 2026-05-08
**Sprint:** 50 (Syn S1 — OCR Foundation)
**Related ADRs:** ADR-007 (Skuggi PII Guardrail) — gates the cloud tiers below.

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

**4-tier hybrid stack with local-first default + opt-in cloud premium.**

| Tier | Engine | License | Cost | Use case |
|:---:|---|---|---|---|
| **1a** | `datalab-to/chandra` (10.5k ⭐) | Apache 2.0 | $0 (local) | Handwriting, complex tables, forms |
| **1b** | `PaddleOCR` PP-OCRv4 (~50k ⭐) | Apache 2.0 | $0 (local) | Thai stock print, fast latency |
| **2** | `gemini-3-flash` | proprietary API | ~$0.001-0.005 / page | Multilingual fallback when local confidence low |
| **3** | `gemini-3.1-pro` | proprietary API | ~$0.05-0.20 / page | High-stakes (legal, critical lab, complex layouts) |

**Smart router** (rule-based, evaluated in order, first match wins):

1. PHI-strict tenant flag set → LOCAL only (Tier 1a/1b)
2. Per-call `--engine` override → that engine
3. Document type known (handwriting / complex_table / form / thai_print) → 1a or 1b
4. Document size >5p OR marked "critical"/"legal" → Tier 3 (Pro) IF tenant `cloud_pro_enabled` else Tier 2 (Flash) else 1a best-effort
5. Local engine confidence <0.70 → Tier 2 (Flash) IF `cloud_flash_enabled` else local + warn
6. Default → 1a chandra → fallback 1b PaddleOCR

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

### E. **4-tier hybrid (CHOSEN)**
- ✅ Local-first default (covers ~85% of routine docs at $0)
- ✅ Opt-in cloud for the 15% hard cases (controlled cost)
- ✅ All-Apache-2.0 local stack preserves Commercial moat
- ✅ Cloud tier reuses existing Heimdall step-up router pattern (Sprint 36)
- 🟡 Two services to maintain locally (chandra + PaddleOCR); router complexity
- 🟡 chandra is newer (~1 yr); accept as monitored risk

## Consequences

### Positive
- **Commercial Enterprise tier protected** — no GPL viral clause exposure
- **PDPA defensible** — default local; cloud requires explicit per-tenant opt-in + Skuggi (ADR-007) PII redaction
- **Cost predictable** — small clinic ~$0-25/mo, hospital ~$50-150/mo, specialty up to $200/mo
- **Reusable pattern** — same Heimdall step-up route works for Sprint 52 Sága (STT) and Sprint 53 vision LLM

### Negative
- **2 local services to maintain** — chandra + PaddleOCR drift, version pinning, ops
- **Router complexity** — rule-based v0 may need ML-based v1 (deferred)
- **chandra Thai accuracy unknown** — no explicit Thai model; mitigation via B-50h benchmark; if Thai CER >20% on chandra, demote to handwriting/tables only

### Mitigations
- B-50h test set: 30 Thai docs (10 print, 10 handwriting, 10 table) × 4 engines = 120-cell benchmark grid before sprint close
- B-50l tenant settings include `pii_mode` (chained to ADR-007 Skuggi) before any cloud call goes live
- B-50m cost guard middleware enforces monthly per-tenant cap
- Quarterly stack review: if chandra matures + Thai support solid → drop PaddleOCR (Sprint 53+)
- If clinician feedback shows chandra inadequate → consider buying Datalab commercial license for surya/marker

## Future revisits

- **2026-Q3:** if chandra Thai accuracy ≥ PaddleOCR after maturity → simplify to chandra-only local
- **2026-Q4:** if Sprint 52 Sága needs reversible PII (voice context) → upgrade Skuggi v1 with HSM keys
- **2027:** if Asgard Commercial moat sufficiently established + Datalab commercial pricing reasonable → re-evaluate surya/marker

## References

- Sprint 50 backlog: [`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md) Sprint 50 section
- ADR-007 Skuggi (gates cloud tiers): [`ADR-007-Skuggi-PII-Guardrail.md`](ADR-007-Skuggi-PII-Guardrail.md)
- chandra: https://github.com/datalab-to/chandra (Apache 2.0)
- PaddleOCR: https://github.com/PaddlePaddle/PaddleOCR (Apache 2.0)
- Asgard roadmap (Syn → Sága → Visual BMI sequence): [`../strategy/roadmap.md`](../strategy/roadmap.md)
