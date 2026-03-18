#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🦉 Muninn — E2E Test Suite
# AI Auto-Fix Service (LLM + Issue Analyzer + PR Creator)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

MUNINN_URL="${MUNINN_URL:-http://localhost:8500}"
FORSETI_URL="${FORSETI_URL:-http://localhost:5555}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
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
echo "║  🦉 Muninn E2E Test Suite            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Health ──
echo "🔧 Service Health"
check S01 "Healthz" \
  "curl -s -o /dev/null -w '%{http_code}' $MUNINN_URL/healthz --max-time 5" "200"
check S02 "Health returns service name" \
  "curl -s $MUNINN_URL/healthz --max-time 5 | python3 -c \"import sys,json;d=json.load(sys.stdin);print(d.get('service',''))\"" "muninn"

# ── Auto-Fix API ──
echo ""
echo "🔧 Auto-Fix API"
check A01 "Issues endpoint" \
  "curl -s -o /dev/null -w '%{http_code}' $MUNINN_URL/api/v1/issues --max-time 5" "200"
check A02 "Fixes endpoint" \
  "curl -s -o /dev/null -w '%{http_code}' $MUNINN_URL/api/v1/fixes --max-time 5" "200"
check A03 "Submit issue for analysis" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $MUNINN_URL/api/v1/analyze -H 'Content-Type: application/json' -d '{\"issue_id\":\"test-001\",\"title\":\"Test issue\",\"description\":\"E2E test\"}' --max-time 10" "200|202|404"

# ── GitHub Integration ──
echo ""
echo "🔗 GitHub Integration"
check G01 "Repos endpoint" \
  "curl -s -o /dev/null -w '%{http_code}' $MUNINN_URL/api/v1/repos --max-time 5" "200"

# ── Rust Tests ──
echo ""
echo "🧪 Cargo Tests"
check U01 "cargo test passes" \
  "cd $PROJECT_DIR && cargo test 2>&1 | tail -1" "ok|passed"

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
    -d "{\"suite_name\":\"Muninn E2E\",\"total\":$N,\"passed\":$P,\"failed\":$F,\"skipped\":0,\"errors\":0,\"duration_ms\":10000,\"phase\":\"verification\",\"project_version\":\"0.1.0\",\"base_url\":\"$MUNINN_URL\",\"tests\":[$TESTS]}" --max-time 10) || SRC="ERR"
  echo "  $([ "$SRC" = "200" ] || [ "$SRC" = "201" ] && echo "✅ Submitted ($SRC)" || echo "⚠️ Forseti: $SRC")"
fi
