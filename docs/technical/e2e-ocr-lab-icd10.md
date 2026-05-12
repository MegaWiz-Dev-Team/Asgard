# E2E — Lab Report Image → Eir → ICD-10-TM

**Sprint 50 B-50j operational verification.**

Validates the full Phase A path lands: clinician uploads a lab report image, Eir extracts the diagnoses, calls Hermodr's **`icd10_tm_lookup`** for **Thai ICD-10-TM** code mapping, and returns codes grounded in the document. This isn't a unit test — it spans Mimir, Bifrost, Syn, Hermodr, Heimdall, plus the deployed MariaDB. Run it as a smoke test after deploying the Sprint 50 stack to OrbStack / staging.

**Why Thai ICD-10-TM (not ICD-10-CM)?** The original draft pointed at Hermodr's `icd10_lookup` (NLM US Clinical Tables — English ICD-10-CM). That's wrong for Thai clinical workflows where claims go to สปสช./HOSxP/MoPH and need the Thai Modification. Sprint 48 (`icd10_codes` table seeded from MoPH anamai-moph-2010, bilingual th+en, Qdrant `icd10-th` with BGE-M3 embeddings) supports Thai correctly; the new Hermodr tool `icd10_tm_lookup` proxies to that. ICD-10-CM tool stays available for international research use.

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

# 4) Ask Eir for ICD-10-TM codes — message body uses the same marker
# format the B-50i dashboard uses, so the agent treats document text and
# query separately. NOTE: prompt asks for icd10_tm_lookup (Thai), not
# the international icd10_lookup (NLM CM).
PROMPT="[Attached Document — extracted via ${ENGINE} (audit_id=${AUDIT})]
${TEXT}
[End of document]

Identify all clinical findings in this lab report and return matching ICD-10-TM codes (Thai Modification — MoPH anamai source). Use the icd10_tm_lookup tool — it accepts Thai or English queries and returns th_label + en_label + DRG mapping. Output as a markdown table with columns: finding | code | th_label | en_label."

curl -s -X POST https://mimir.asgard.internal/api/v1/agents/chat \
  -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg msg "$PROMPT" '{tier: 2, message: $msg, persona: "eir"}')"

# Or call Mimir's Thai ICD-10-TM endpoint directly to spot-check coverage:
curl -s -G https://mimir.asgard.internal/api/v1/icd10/lookup \
  -H "X-Tenant-Id: asgard_medical" \
  --data-urlencode "q=ไข้หวัดใหญ่" \
  --data-urlencode "locale=both" \
  --data-urlencode "limit=5"
```

Look for `[A-Z][0-9]{2}(\.[0-9]+)?` patterns in `content`.

## Acceptance criteria (sprint plan)

> B-50j — End-to-end test: lab report image → Eir-medtech → ICD-10 codes (chains B-48h FHIR)

Practical interpretation, given the actual agent roster + Thai ICD-10-TM coding (not ICD-10-CM):

- [ ] Image → `extracted_text` returned by Syn (any engine) — verifies B-50a/c/e
- [ ] Agent response contains ≥1 ICD-10-shaped code AND the agent actually invoked `icd10_tm_lookup` (Thai), not `icd10_lookup` (CM) — verifies B-50g (allowlist) + Sprint 48 ICD-10-TM backend
- [ ] Laminar shows the span tree: Bifrost → Mimir → Syn → engine, then Bifrost → Heimdall → Eir → Hermodr `icd10_tm_lookup` calls
- [ ] Returned codes have a `th_label` field populated (Thai ICD-10-TM source-version `anamai-moph-2010` carries bilingual labels)
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
