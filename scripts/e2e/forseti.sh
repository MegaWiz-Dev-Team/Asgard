#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ⚖️ Forseti — E2E Test Suite
# Test Dashboard & Result Aggregation
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

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
echo "║  ⚖️ Forseti E2E Test Suite           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Health ──
echo "🔧 Service Health"
check S01 "Dashboard reachable" \
  "curl -s -o /dev/null -w '%{http_code}' $FORSETI_URL/ --max-time 5" "200"
check S02 "Container running" \
  "docker inspect asgard_forseti --format '{{.State.Status}}'" "running"

# ── Dashboard UI ──
echo ""
echo "📊 Dashboard"
check D01 "Returns HTML" \
  "curl -s $FORSETI_URL/ --max-time 5 | grep -c 'Forseti'" "[1-9]"
check D02 "Has chart.js" \
  "curl -s $FORSETI_URL/ --max-time 5 | grep -c 'chart\|Chart'" "[1-9]"

# ── API ──
echo ""
echo "🔌 REST API"
check A01 "GET /api/runs" \
  "curl -s -o /dev/null -w '%{http_code}' $FORSETI_URL/api/runs --max-time 5" "200"
check A02 "Returns JSON array" \
  "curl -s $FORSETI_URL/api/runs --max-time 5 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if isinstance(d,list) else 'no')\"" "yes"
check A03 "Submit test run" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $FORSETI_URL/api/runs -H 'Content-Type: application/json' -d '{\"suite_name\":\"E2E Self-Test\",\"total\":1,\"passed\":1,\"failed\":0,\"skipped\":0,\"errors\":0,\"duration_ms\":100,\"phase\":\"verification\",\"tests\":[{\"test_id\":\"SELF\",\"name\":\"Self-test\",\"status\":\"pass\"}]}' --max-time 5" "200|201"
check A04 "Submitted run appears" \
  "curl -s $FORSETI_URL/api/runs --max-time 5 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if any('Self-Test' in r.get('suite_name','') or 'E2E Self' in r.get('suite_name','') for r in d) else 'no')\"" "yes"

# ── Data Integrity ──
echo ""
echo "🔒 Data Integrity"
check I01 "Runs have test_count" \
  "curl -s $FORSETI_URL/api/runs --max-time 5 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if d and 'total' in d[0] else 'no')\"" "yes"

# ── Unit Tests ──
echo ""
echo "🧪 Unit Tests"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
check U01 "pytest passes" \
  "cd $PROJECT_DIR && .venv/bin/python -m pytest tests/ -q --tb=no -x 2>&1 | tail -1" "passed"

# ── Results ──
echo ""
echo "═══════════════════════════════════════"
echo "  $P/$N passed, $F failed"
echo "═══════════════════════════════════════"
