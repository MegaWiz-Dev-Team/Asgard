#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🏰 Asgard — UI E2E Tests
# Visual verification of all dashboards via Ratatoskr browser API
# Requires: Ratatoskr running on :9200
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RATATOSKR_URL="${RATATOSKR_URL:-http://localhost:9200}"
FORSETI_URL="${FORSETI_URL:-http://localhost:5555}"

# Load .env
if [ -f "$SCRIPT_DIR/../../.env" ]; then
  while IFS='=' read -r key value; do
    if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ "$key" =~ ^[A-Za-z_] ]]; then
      value="${value%\"}" ; value="${value#\"}"
      export "$key=$value" 2>/dev/null || true
    fi
  done < "$SCRIPT_DIR/../../.env"
fi

P=0; F=0; N=0; RES=()
SCREENSHOTS_DIR="/tmp/asgard_ui_tests"
mkdir -p "$SCREENSHOTS_DIR"

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

# Helper: scrape a page via Ratatoskr and check for content
scrape_check() {
  local url=$1 expected=$2
  curl -s -X POST "$RATATOSKR_URL/api/v1/scrape" \
    -H "Content-Type: application/json" \
    -d "{\"url\":\"$url\",\"extract_text\":true}" \
    --max-time 30 | python3 -c "
import sys,json
d=json.load(sys.stdin)
text=(d.get('text','') or '') + ' ' + (d.get('title','') or '') + ' ' + (d.get('html','') or '')
print('found' if '$expected'.lower() in text.lower() else 'not_found')
" 2>/dev/null || echo "ERR"
}

# Helper: take screenshot via Ratatoskr
screenshot() {
  local url=$1 name=$2
  curl -s -X POST "$RATATOSKR_URL/api/v1/screenshot" \
    -H "Content-Type: application/json" \
    -d "{\"url\":\"$url\",\"full_page\":true}" \
    --max-time 30 \
    -o "$SCREENSHOTS_DIR/$name.png" 2>/dev/null
  [ -s "$SCREENSHOTS_DIR/$name.png" ] && echo "saved" || echo "failed"
}

echo "╔══════════════════════════════════════════════╗"
echo "║  🖥️  Asgard UI E2E Tests                     ║"
echo "║  via Ratatoskr Shared Browser (:9200)        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Pre-check: Ratatoskr ──
echo "🐿️ Pre-check: Ratatoskr"
check PRE "Ratatoskr available" \
  "curl -s $RATATOSKR_URL/healthz | python3 -c \"import sys,json;print(json.load(sys.stdin)['status'])\"" "ok"

if [ "$P" -eq 0 ]; then
  echo ""
  echo "❌ Ratatoskr not available — cannot run UI tests"
  exit 1
fi

# ═══════════════════════════════════
# 🧠 Mimir Dashboard (:3001)
# ═══════════════════════════════════
echo ""
echo "🧠 Mimir Dashboard (http://localhost:3001)"
check MD01 "Dashboard loads" \
  "scrape_check 'http://host.docker.internal:3001' 'mimir'" "found"
check MD02 "Has navigation" \
  "scrape_check 'http://host.docker.internal:3001' 'dashboard'" "found"
check MD03 "Screenshot captured" \
  "screenshot 'http://host.docker.internal:3001' 'mimir_dashboard'" "saved"

# ═══════════════════════════════════
# ⚖️ Forseti Dashboard (:5555)
# ═══════════════════════════════════
echo ""
echo "⚖️ Forseti Dashboard (http://localhost:5555)"
check FD01 "Dashboard loads" \
  "scrape_check 'http://host.docker.internal:5555' 'forseti'" "found"
check FD02 "Shows test runs" \
  "scrape_check 'http://host.docker.internal:5555' 'pass'" "found"
check FD03 "Has chart" \
  "scrape_check 'http://host.docker.internal:5555' 'chart'" "found"
check FD04 "Screenshot captured" \
  "screenshot 'http://host.docker.internal:5555' 'forseti_dashboard'" "saved"

# ═══════════════════════════════════
# 🏥 Eir / OpenEMR (:8300)
# ═══════════════════════════════════
echo ""
echo "🏥 Eir / OpenEMR (http://localhost:8300)"
check EI01 "OpenEMR loads" \
  "scrape_check 'http://host.docker.internal:8300' 'openemr'" "found"
check EI02 "Login page visible" \
  "scrape_check 'http://host.docker.internal:8300' 'login'" "found"
check EI03 "Screenshot captured" \
  "screenshot 'http://host.docker.internal:8300' 'eir_openemr'" "saved"

# ═══════════════════════════════════
# 🌳 Yggdrasil (:8085)
# ═══════════════════════════════════
echo ""
echo "🌳 Yggdrasil (http://localhost:8085)"
check YG01 "Login page loads" \
  "scrape_check 'http://host.docker.internal:8085' 'login'" "found"
check YG02 "Screenshot captured" \
  "screenshot 'http://host.docker.internal:8085' 'yggdrasil_login'" "saved"

# ── Results ──
echo ""
echo "═══════════════════════════════════════"
echo "  $P/$N passed, $F failed"
echo "  Screenshots: $SCREENSHOTS_DIR/"
echo "═══════════════════════════════════════"

# ── Submit to Forseti ──
if curl -s "$FORSETI_URL/" > /dev/null 2>&1; then
  echo ""
  echo "📊 Submitting to Forseti..."
  TESTS=$(printf '%s,' "${RES[@]}" | sed 's/,$//')
  SRC=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FORSETI_URL/api/runs" \
    -H "Content-Type: application/json" \
    -d "{\"suite_name\":\"Asgard UI E2E\",\"total\":$N,\"passed\":$P,\"failed\":$F,\"skipped\":0,\"errors\":0,\"duration_ms\":60000,\"phase\":\"verification\",\"project_version\":\"0.2.0\",\"base_url\":\"http://localhost\",\"tests\":[$TESTS]}" --max-time 10) || SRC="ERR"
  echo "  $([ "$SRC" = "200" ] || [ "$SRC" = "201" ] && echo "✅ Submitted ($SRC)" || echo "⚠️ Forseti: $SRC")"
fi

echo ""
echo "📸 Screenshots saved to: $SCREENSHOTS_DIR/"
ls -la "$SCREENSHOTS_DIR/"*.png 2>/dev/null | awk '{print "  " $NF " (" $5 " bytes)"}'
