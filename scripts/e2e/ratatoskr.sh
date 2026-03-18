#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🐿️ Ratatoskr — E2E Test Suite
# Shared Browser Service (Rust local / Python Docker)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

RATATOSKR_URL="${RATATOSKR_URL:-http://localhost:9200}"
FORSETI_URL="${FORSETI_URL:-http://localhost:5555}"
P=0; F=0; N=0; RES=()

check() {
  local id=$1 nm="$2" val
  N=$((N+1))
  val=$(eval "$3" 2>/dev/null) || val="ERR"
  if echo "$val" | grep -qE "$4"; then
    P=$((P+1)); echo "  ✅ $id: $nm"
    RES+=("{\"test_id\":\"$id\",\"name\":\"$nm\",\"status\":\"pass\"}")
  else
    F=$((F+1)); echo "  ❌ $id: $nm (got: $val)"
    RES+=("{\"test_id\":\"$id\",\"name\":\"$nm\",\"status\":\"fail\"}")
  fi
}

echo "╔══════════════════════════════════════╗"
echo "║  🐿️ Ratatoskr E2E Test Suite        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Health ──
echo "🔧 Service Health"
check S01 "Healthz returns ok" \
  "curl -s $RATATOSKR_URL/healthz | python3 -c \"import sys,json;print(json.load(sys.stdin)['status'])\"" "ok"
check S02 "Service name correct" \
  "curl -s $RATATOSKR_URL/healthz | python3 -c \"import sys,json;print(json.load(sys.stdin)['service'])\"" "ratatoskr"
check S03 "Container running" \
  "docker inspect asgard_ratatoskr --format '{{.State.Status}}'" "running"

# ── Fetch API (no browser) ──
echo ""
echo "📡 Fetch API (/api/v1/fetch)"
check F01 "Fetch example.com" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $RATATOSKR_URL/api/v1/fetch -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 10" "200"
check F02 "Fetch returns HTML" \
  "curl -s -X POST $RATATOSKR_URL/api/v1/fetch -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 10 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if 'Example' in d.get('html','') else 'no')\"" "yes"
check F03 "Fetch returns title" \
  "curl -s -X POST $RATATOSKR_URL/api/v1/fetch -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 10 | python3 -c \"import sys,json;print(json.load(sys.stdin).get('title',''))\"" "Example"

# ── Scrape API (with browser) ──
echo ""
echo "🌐 Scrape API (/api/v1/scrape)"
check B01 "Scrape example.com" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $RATATOSKR_URL/api/v1/scrape -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 30" "200"
check B02 "Scrape extracts text" \
  "curl -s -X POST $RATATOSKR_URL/api/v1/scrape -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\",\"extract_text\":true}' --max-time 30 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if d.get('text') else 'no')\"" "yes"

# ── Screenshot API ──
echo ""
echo "📸 Screenshot API (/api/v1/screenshot)"
check P01 "Screenshot returns image" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $RATATOSKR_URL/api/v1/screenshot -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 30" "200"

# ── Error Handling ──
echo ""
echo "⚠️ Error Handling"
check E01 "Invalid URL returns error" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $RATATOSKR_URL/api/v1/fetch -H 'Content-Type: application/json' -d '{\"url\":\"not-a-url\"}' --max-time 10" "4[0-9][0-9]|500"
check E02 "Missing body returns 4xx" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $RATATOSKR_URL/api/v1/fetch --max-time 5" "4[0-9][0-9]"

# ── Results ──
echo ""
echo "═══════════════════════════════════════"
echo "  $P/$N passed, $F failed"
echo "═══════════════════════════════════════"

# ── Submit to Forseti ──
if curl -s "$FORSETI_URL/" > /dev/null 2>&1; then
  echo ""
  echo "📊 Submitting to Forseti..."
  TESTS=$(printf '%s,' "${RES[@]}" | sed 's/,$//')
  SRC=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FORSETI_URL/api/runs" \
    -H "Content-Type: application/json" \
    -d "{\"suite_name\":\"Ratatoskr E2E\",\"total\":$N,\"passed\":$P,\"failed\":$F,\"skipped\":0,\"errors\":0,\"duration_ms\":30000,\"phase\":\"verification\",\"project_version\":\"0.1.0\",\"base_url\":\"$RATATOSKR_URL\",\"tests\":[$TESTS]}" --max-time 10) || SRC="ERR"
  echo "  $([ "$SRC" = "200" ] || [ "$SRC" = "201" ] && echo "✅ Submitted ($SRC)" || echo "⚠️ Forseti: $SRC")"
fi
