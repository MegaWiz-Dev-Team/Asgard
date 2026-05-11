#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🩺 Sprint 50 B-50j — E2E: Lab Report Image → Eir → ICD-10
# Chains: Syn OCR → Mimir agent chat → Hermodr icd10_lookup
# ═══════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/e2e/lab_icd10.sh path/to/lab.png [--verbose] [--persona eir-cardio]
#
# Exit codes:
#   0 — OCR succeeded AND ≥1 ICD-10-shaped code in response
#   1 — OCR failed or transport error
#   2 — Agent responded but produced no ICD-10 code
#
# Env overrides:
#   SYN_URL         (default: https://syn.asgard.internal)
#   MIMIR_URL       (default: https://mimir.asgard.internal)
#   TENANT_ID       (default: asgard_medical)
#   PERSONA         (default: eir)

set -euo pipefail

SYN_URL="${SYN_URL:-https://syn.asgard.internal}"
MIMIR_URL="${MIMIR_URL:-https://mimir.asgard.internal}"
TENANT_ID="${TENANT_ID:-asgard_medical}"
PERSONA="${PERSONA:-eir}"
VERBOSE=0

# ─── arg parse ───────────────────────────────────────────────────
IMG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --tenant) TENANT_ID="$2"; shift 2 ;;
    -h|--help)
      sed -n '4,20p' "$0"
      exit 0 ;;
    *) IMG="$1"; shift ;;
  esac
done

if [[ -z "$IMG" || ! -f "$IMG" ]]; then
  echo "❌ usage: $0 path/to/lab_report.png [--verbose] [--persona name]"
  exit 1
fi

log()  { echo "  $*" >&2; }
warn() { echo "⚠️  $*" >&2; }
fail() { echo "❌ $*" >&2; exit "${2:-1}"; }
ok()   { echo "✅ $*" >&2; }

# ─── 1) Encode image ──────────────────────────────────────────────
log "Encoding $IMG ..."
BASE64=$(base64 -i "$IMG" 2>/dev/null | tr -d '\n')
[[ -z "$BASE64" ]] && fail "base64 encode failed"

# ─── 2) Call Syn OCR ──────────────────────────────────────────────
log "POST $SYN_URL/api/v1/syn/ocr/extract-json (tenant=$TENANT_ID)"
OCR_REQ=$(jq -n --arg b "$BASE64" --arg f "$(basename "$IMG")" \
  '{image_base64: $b, filename: $f}')

OCR_RESP=$(curl -sS -X POST "$SYN_URL/api/v1/syn/ocr/extract-json" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -H "Content-Type: application/json" \
  --data "$OCR_REQ" \
  -w '\n%{http_code}')

HTTP=$(echo "$OCR_RESP" | tail -n1)
BODY=$(echo "$OCR_RESP" | sed '$d')

if [[ "$HTTP" != "200" ]]; then
  echo "$BODY" >&2
  fail "Syn OCR returned HTTP $HTTP" 1
fi

STATUS=$(echo "$BODY" | jq -r '.status // "unknown"')
if [[ "$STATUS" != "succeeded" ]]; then
  echo "$BODY" >&2
  fail "Syn OCR status=$STATUS (expected succeeded)" 1
fi

ENGINE=$(echo "$BODY"  | jq -r '.engine_used // "?"')
AUDIT=$(echo "$BODY"   | jq -r '.audit_id // ""')
COST=$(echo "$BODY"    | jq -r '.cost_usd // 0')
LAT=$(echo "$BODY"     | jq -r '.latency_ms // 0')
TEXT=$(echo "$BODY"    | jq -r '.extracted_text // ""')
TEXTLEN=${#TEXT}

ok "OCR succeeded — engine=$ENGINE audit=$AUDIT cost_usd=$COST latency=${LAT}ms text_len=$TEXTLEN"

if [[ "$TEXTLEN" -lt 20 ]]; then
  warn "Extracted text is very short ($TEXTLEN chars) — agent unlikely to find ICD codes"
fi

if [[ "$VERBOSE" -eq 1 ]]; then
  log "─── extracted text ───"
  echo "$TEXT" | sed 's/^/    /' >&2
  log "──────────────────────"
fi

# ─── 3) Call Mimir agent chat ─────────────────────────────────────
PROMPT="[Attached Document — extracted via ${ENGINE} (audit_id=${AUDIT})]
${TEXT}
[End of document]

Identify all clinical findings in this lab report and return matching ICD-10-CM codes. Use the icd10_lookup tool if you have it. Output as a markdown table with columns: finding | code | description."

log "POST $MIMIR_URL/api/v1/agents/chat (persona=$PERSONA)"
CHAT_REQ=$(jq -n --arg msg "$PROMPT" --arg p "$PERSONA" \
  '{tier: 2, message: $msg, persona: $p}')

CHAT_RESP=$(curl -sS -X POST "$MIMIR_URL/api/v1/agents/chat" \
  -H "X-Tenant-Id: $TENANT_ID" \
  -H "Content-Type: application/json" \
  --data "$CHAT_REQ" \
  -w '\n%{http_code}')

HTTP=$(echo "$CHAT_RESP" | tail -n1)
BODY=$(echo "$CHAT_RESP" | sed '$d')

if [[ "$HTTP" != "200" ]]; then
  echo "$BODY" >&2
  fail "Mimir agent chat returned HTTP $HTTP" 1
fi

CONTENT=$(echo "$BODY" | jq -r '.content // ""')
[[ -z "$CONTENT" ]] && fail "agent response had no content" 1

if [[ "$VERBOSE" -eq 1 ]]; then
  log "─── agent response ───"
  echo "$CONTENT" | sed 's/^/    /' >&2
  log "──────────────────────"
fi

# ─── 4) Verify ICD-10 codes present ──────────────────────────────
CODES=$(echo "$CONTENT" | grep -oE '\b[A-TV-Z][0-9]{2}(\.[0-9A-Z]{1,4})?\b' | sort -u || true)

if [[ -z "$CODES" ]]; then
  warn "No ICD-10-shaped codes found in response"
  warn "  (engine=$ENGINE, persona=$PERSONA, text_len=$TEXTLEN)"
  warn "  Re-run with --verbose to inspect the OCR text + agent output"
  exit 2
fi

CODE_COUNT=$(echo "$CODES" | wc -l | tr -d ' ')
ok "Found $CODE_COUNT ICD-10 code(s): $(echo "$CODES" | tr '\n' ' ')"
exit 0
