# ADR-007 — Skuggi PII Guardrail (Pre-LLM Blind)

**Status:** Accepted
**Date:** 2026-05-08
**Sprint:** 50b (parallel with Sprint 50 Syn S1)
**Related ADRs:** ADR-006 (Syn OCR Stack) — Skuggi gates ADR-006's cloud tiers (2/3).

## Context

Sprint 50 introduces cloud OCR (Gemini Flash + Pro) for hard cases that
local engines (chandra, PaddleOCR) can't handle well. Sending Thai
medical documents to Google's cloud is a **PHI risk under PDPA**:
documents may contain face photos, Thai national IDs, MRN/HN, person
names, addresses, signatures.

The existing `ocr_phi_strict` tenant flag is **all-or-nothing** — disabling
it opens cloud calls fully, enabling renders Sprint 50's cloud tier
unusable. Hospitals need granular **"redact then cloud-OK"** posture.

## Decision

**🌑 Skuggi** — Heimdall pre-LLM middleware that masks PII in image and
text payloads BEFORE any cloud LLM call. Norse "shadow" — hides PII in
shadow before the LLM sees the document.

### Pattern: Heimdall middleware (in-process Rust)

- Runs inline with every cloud-bound LLM call (OCR, voice STT, vision)
- Single audit point for compliance
- No extra hop / latency penalty
- Reuses existing per-tenant settings + JWT context

### Image PII stack (zero new external libraries)

| Component | Tool | Notes |
|---|---|---|
| Face detection | OpenCV YuNet (built-in OpenCV ≥4.7) | reuse — Sprint 50 already pulls OpenCV |
| Thai-ID/MRN box detection | PaddleOCR text + bounding boxes | reuse — Sprint 50 PaddleOCR already deployed |
| Pattern matching | Rust regex on extracted text | pure in-process |
| Blur | OpenCV `cv2.GaussianBlur` | reuse |

### Text PII stack (1 new sidecar)

**Tier 1 — Rust regex (in-process Heimdall middleware, <1ms):**
- Thai national ID 13-digit: `^[1-8]-?\d{4}-?\d{5}-?\d{2}-?\d{1}$`
- Phone: Thai patterns + +66 international
- MRN/HN: tenant-configurable regex via `pii_custom_patterns`
- Email, plate number, DOB

**Tier 2 — PyThaiNLP sidecar (port 8086, ~50-100ms, Python):**
- Thai person name detection (given + family)
- Thai address parsing (house number + soi + tambon + amphoe)
- Hospital/clinic name recognition
- **Triggered conditionally** when Tier 1 has low coverage suspicion (~10-20% of calls)

### Modes

| Mode | Behavior | When to use |
|---|---|---|
| `off` | No redaction (legacy behavior) | NEVER as default |
| `detect-only` | Log PII, don't redact | dev/staging tenants |
| `mask-and-send` | Redact + send to cloud | ✅ **default for new tenants** |
| `block-on-pii` | Fail call if any PII found | strictest — high-PHI hospitals |

### Reversibility

**v0: Irreversible (one-way)** — PII discarded; placeholder tokens remain
in cloud response. Original document lives on disk in Vault/Mimir for
re-reference.

**Why irreversible v0 fits OCR specifically:**
- OCR is batch task — return text structure, no contextual reasoning
- Local OCR (chandra/PaddleOCR) already extracted base text with PII intact locally
- Cloud OCR is for "fix the hard parts" — placeholder tokens fine
- Mapping table = NEW PHI key store with rotation/audit/HSM burden — not justified for OCR

**v1 (Sprint 52+):** Reversible mapping with HSM-protected keys for voice
STT, chat agents, vision LLM where contextual reasoning needs PII context.

## Options considered

### A. PHI-strict flag only (status quo)
- ✅ Simple
- ❌ All-or-nothing — defeats cloud tier; tenants who want cloud OCR with safety left without options
- **Rejected:** insufficient granularity

### B. Microsoft Presidio
- ✅ Apache 2.0 · mature · multi-language
- ❌ Python-only (Asgard is Rust-first); Thai support weak; heavyweight framework for our pattern needs
- **Rejected:** stack misalignment

### C. Cloud DLP (AWS Comprehend / GCP DLP)
- ✅ Mature, accurate
- ❌ Defeats the purpose — sends PII to cloud to detect PII
- **Rejected:** privacy paradox

### D. Hugging Face PII BERT models
- ✅ Better than regex for ambiguous cases
- ❌ GPU-heavy, slow on Mac mini
- **Rejected for v0:** too heavy; revisit Sprint 53+ if needed

### E. **Rust regex (Tier 1) + PyThaiNLP sidecar (Tier 2) — CHOSEN**
- ✅ Rust-first aligned with Asgard pattern
- ✅ Tier 1 fast (<1ms) for known-pattern cases (~80% of redactions)
- ✅ Tier 2 PyThaiNLP best-in-class for Thai NER (Apache 2.0)
- ✅ Image stack reuses OpenCV (zero new lib)
- 🟡 PyThaiNLP sidecar = 1 new Python service; mitigated by conditional invocation

## Consequences

### Positive
- **PDPA defensibility** — explicit per-tenant `pii_mode` + audit trail per redaction
- **Sprint 50 cloud tier becomes usable** — without Skuggi, cloud OCR was unusable for PHI-aware hospitals
- **Pattern reusable** — Sprint 52 Sága (voice STT) + Sprint 53 vision LLM + future Eir cloud step-up all chain Skuggi
- **No new external lib for image** — net new deps = 1 (PyThaiNLP)
- **Latency budget preserved** — <1ms Tier 1 + ≤300ms Tier 2 (only when triggered) ≈ p50 ≤300ms overhead

### Negative
- **PyThaiNLP sidecar** — extra service to maintain
- **Irreversible v0** — cloud responses have placeholder tokens; user must reference local doc for original PII
- **Tier 2 latency variability** — 50-100ms per call when triggered; mitigated by conditional firing

### Mitigations
- Conditional Tier 2 invocation (only on Tier 1 low-coverage signal)
- Per-tenant Tier 2 disable flag if hospital prefers Tier 1 only (latency hard cap)
- v1 (Sprint 50.5+): introduce reversible mapping behind HSM if voice/chat use cases require it
- Quarterly review of Tier 2 NER model drift (PyThaiNLP releases)

## Acceptance gates (block sprint close until met)

- [ ] Detection recall ≥98% on B-50b-7 test set (false negatives = PHI leak)
- [ ] Detection precision ≥90% (false positives manageable)
- [ ] Sprint 50 cloud OCR (B-50k) MUST chain through Skuggi when tenant `pii_mode != off`
- [ ] PHI-strict tenant: 100% of cloud calls blocked when `pii_mode = block-on-pii` AND PII detected (verified 20 PHI-marked test cases)
- [ ] Audit row per redaction with full context

## Future revisits

- **2026-Q3 (Sprint 52):** Sága voice introduces reversible v1 needs — implement HSM-protected mapping table
- **2026-Q4 (Sprint 53):** vision LLM may need Tier 3 (BERT-based PII) for image-with-Thai-text edge cases
- **2027:** if PyThaiNLP latency unacceptable at scale → fine-tune Thai NER on hospital corpus, port to ONNX

## References

- Sprint 50b backlog: [`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md) Sprint 50b section
- ADR-006 (gated by this ADR's cloud tiers): [`ADR-006-Syn-OCR-Stack.md`](ADR-006-Syn-OCR-Stack.md)
- OpenCV YuNet: https://github.com/opencv/opencv/tree/4.x/samples/dnn (built-in face detector)
- PyThaiNLP: https://github.com/PyThaiNLP/pythainlp (Apache 2.0)
- Asgard observability stack (Týr/SIEM integration for audit log): [`observability_stack.md`](observability_stack.md)
