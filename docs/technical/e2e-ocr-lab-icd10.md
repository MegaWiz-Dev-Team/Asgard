# E2E — Lab Report Image → Eir → ICD-10

**Sprint 50 B-50j operational verification.**

Validates the full Phase A path lands: clinician uploads a lab report image, Eir extracts the diagnoses, calls Hermodr's `icd10_lookup` for code mapping, and returns ICD-10 codes grounded in the document. This isn't a unit test — it spans Mimir, Bifrost, Syn, Hermodr, Heimdall, plus the deployed MariaDB. Run it as a smoke test after deploying the Sprint 50 stack to OrbStack / staging.

## Prerequisites

- Asgard stack up on OrbStack K8s:
  - `mimir-api`, `bifrost`, `syn-api` (+ PaddleOCR sidecar, Typhoon-OCR via Ollama), `heimdall-gateway`, `hermodr`
  - MariaDB seeded with sprint38 Eir specialists + sprint50 OCR foundation + B-50g allowlist migration
- A test lab report image (any Thai/English clinical report; the smaller the better — keep under ~2 MB to avoid encoding pain)
- Tailnet access or `kubectl port-forward` to reach the services (see `Asgard/docs/technical/port-allocation-startup.md`)

## Quick smoke test (shell script)

```bash
./scripts/e2e_lab_icd10.sh path/to/lab_report.png
```

The script chains: image → Syn OCR (Tier 1 PaddleOCR by default) → Mimir `/agents/chat` with the extracted text + a "give me ICD-10 codes" prompt → grep response for ICD-10 patterns.

Exit codes:

- `0` — OCR succeeded AND at least one ICD-10-shaped code matched (`[A-Z]\d{2}(\.\d+)?`)
- `1` — OCR failure (Syn returned engine_failed / 502 / non-2xx)
- `2` — Agent returned without any ICD-10 code (could be: low-confidence OCR, agent didn't call `icd10_lookup`, or the report had no codeable findings)

Code 2 is the most useful failure mode — it means the wiring works but the AI didn't deliver. Investigate by:

1. Re-running with `-v` flag to dump the raw chat response (look at the `[Attached Document]` block — is the OCR text legible?)
2. Checking Laminar (Sága) trace at <https://laminar.asgard.internal/projects> — did the agent call `icd10_lookup` at all?
3. Trying with a different specialty agent (`?persona=eir-cardio` vs `?persona=eir-internal-medicine` once renamed) — sometimes specialty framing drives more aggressive code-mapping

## Manual variant (curl)

If you want to inspect each stage:

```bash
# 1) Encode image
BASE64=$(base64 -i lab_report.png | tr -d '\n')

# 2) OCR via Syn (smart router picks engine)
curl -s -X POST https://syn.asgard.internal/api/v1/syn/ocr/extract-json \
  -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\":\"$BASE64\",\"filename\":\"lab.png\"}" | tee /tmp/ocr.json
# Expect: { audit_id, engine_used, status: "succeeded", extracted_text, cost_usd, latency_ms, ... }

# 3) Pull extracted text
TEXT=$(jq -r '.extracted_text' /tmp/ocr.json)
AUDIT=$(jq -r '.audit_id' /tmp/ocr.json)
ENGINE=$(jq -r '.engine_used' /tmp/ocr.json)

# 4) Ask Eir for ICD-10 codes — message body uses the same marker
# format the B-50i dashboard uses, so the agent treats document text and
# query separately.
PROMPT="[Attached Document — extracted via ${ENGINE} (audit_id=${AUDIT})]
${TEXT}
[End of document]

Identify all clinical findings in this lab report and return matching ICD-10-CM codes. Use the icd10_lookup tool. Output as a markdown table with columns: finding | code | description."

curl -s -X POST https://mimir.asgard.internal/api/v1/agents/chat \
  -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg msg "$PROMPT" '{tier: 2, message: $msg, persona: "eir"}')"
```

Look for `[A-Z][0-9]{2}(\.[0-9]+)?` patterns in `content`.

## Acceptance criteria (sprint plan)

> B-50j — End-to-end test: lab report image → Eir-medtech → ICD-10 codes (chains B-48h FHIR)

Practical interpretation, given the actual agent roster:

- [ ] Image → `extracted_text` returned by Syn (any engine) — verifies B-50a/c/e
- [ ] Agent response contains ≥1 ICD-10-shaped code — verifies B-50g (allowlist) + Hermodr `icd10_lookup` + B-48h ICD-10 backend
- [ ] Laminar shows the span tree: Bifrost → Mimir → Syn → engine, then Bifrost → Heimdall → Eir → Hermodr `icd10_lookup` calls
- [ ] If `cloud_flash_enabled=true` and budget headroom: cost_usd > 0 visible on dashboard `/analytics/llm` Recent OCR Calls table (post-#268)

## What this test does NOT cover

- **Accuracy of OCR or coding.** This verifies the wire — not that codes match the clinician's expert read. CER and code-precision live in B-50h (clinician-curated test set) which is gated on partner data.
- **Multi-page PDFs.** Out of scope for Sprint 50 (deferred).
- **PHI strict path.** That's its own verification — enable `ocr_phi_strict` for a test tenant and confirm the Bifrost transparent path returns 403 (see B-50d Bifrost #13).
- **Budget exceeded path.** Set a small `ocr_monthly_cloud_budget_usd` and run repeatedly until 402 (see B-50m Mimir #266).

## Companion artifacts

- **Image:** `tests/fixtures/lab_report_sample.png` (anonymized; if absent, supply your own)
- **Script:** `scripts/e2e_lab_icd10.sh`
- **Laminar dashboard:** <https://laminar.asgard.internal/projects>
- **OCR Cost Guard dashboard:** <https://mimir.asgard.internal/analytics/llm> → OCR tab (post-#267)
