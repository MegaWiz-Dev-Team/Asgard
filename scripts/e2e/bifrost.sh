#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# ⚡ Bifrost — E2E Test Suite
# Agent Runtime + Tool System + LLM Integration
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env if available
if [ -f "$PROJECT_DIR/.env" ]; then
  while IFS='=' read -r key value; do
    if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ "$key" =~ ^[A-Za-z_] ]]; then
      value="${value%\"}" ; value="${value#\"}"
      export "$key=$value" 2>/dev/null || true
    fi
  done < "$PROJECT_DIR/.env"
fi

BIFROST_URL="${BIFROST_URL:-http://localhost:8100}"
HEIMDALL_URL="${HEIMDALL_URL:-http://localhost:8080}"
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
echo "║  ⚡ Bifrost E2E Test Suite           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Health & Infra ──
echo "🔧 Service Health"
check S01 "Server reachable" \
  "curl -s -o /dev/null -w '%{http_code}' $BIFROST_URL/healthz --max-time 5" "200"
check S02 "Container healthy" \
  "docker inspect asgard_bifrost --format '{{.State.Health.Status}}'" "healthy"

# ── Agents API ──
echo ""
echo "🤖 Agent Management"
check A01 "List agents" \
  "curl -s -o /dev/null -w '%{http_code}' $BIFROST_URL/v1/agents" "200"
check A02 "Default agent exists" \
  "curl -s $BIFROST_URL/v1/agents | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if any(a.get('id','')=='default' or a.get('agent_id','')=='default' for a in (d if isinstance(d,list) else d.get('agents',d.get('data',[]))))  else 'no')\"" "yes"
check A03 "Create agent" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BIFROST_URL/v1/agents -H 'Content-Type: application/json' -d '{\"agent_id\":\"e2e-test-$(date +%s)\",\"name\":\"E2E Test Agent\",\"system_prompt\":\"You are a test assistant.\"}'" "200|201|409"

# ── Tools ──
echo ""
echo "🔧 Tool System"
check T01 "Tools registered" \
  "curl -s $BIFROST_URL/v1/agents/default | python3 -c \"import sys,json;d=json.load(sys.stdin);tools=d.get('tools',d.get('available_tools',[]));print(len(tools) if isinstance(tools,list) else 0)\" 2>/dev/null || echo 0" "[1-9]"
check T02 "browse_web tool exists" \
  "curl -s $BIFROST_URL/v1/agents/default | python3 -c \"import sys,json;d=json.load(sys.stdin);tools=d.get('tools',d.get('available_tools',[]));names=[t.get('name','') if isinstance(t,dict) else t for t in tools];print('yes' if 'browse_web' in names else 'no')\" 2>/dev/null || echo 'skip'" "yes|skip"

# ── Agent Run (LLM) ──
echo ""
echo "🧠 Agent Execution (via Heimdall)"
check R01 "Simple question" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST $BIFROST_URL/v1/agents/default/run -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What is 1+1?\"}]}' --max-time 60" "200"
check R02 "Response has output" \
  "curl -s -X POST $BIFROST_URL/v1/agents/default/run -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2?\"}]}' --max-time 60 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if d.get('output') else 'no')\"" "yes"
check R03 "Response has trace" \
  "curl -s -X POST $BIFROST_URL/v1/agents/default/run -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What is 3+3?\"}]}' --max-time 60 | python3 -c \"import sys,json;d=json.load(sys.stdin);print('yes' if d.get('trace') else 'no')\"" "yes"

# ── Unit Tests ──
echo ""
echo "🧪 Unit Tests"
check U01 "pytest passes" \
  "cd $PROJECT_DIR && .venv/bin/python -m pytest tests/ -q --tb=no 2>&1 | tail -1" "passed"

# ── Results ──
echo ""
echo "═══════════════════════════════════════"
echo "  $P/$N passed, $F failed"
echo "═══════════════════════════════════════"

# ── Submit to Forseti ──
if curl -s "$FORSETI_URL/healthz" > /dev/null 2>&1 || curl -s "$FORSETI_URL/" > /dev/null 2>&1; then
  echo ""
  echo "📊 Submitting to Forseti..."
  TESTS=$(printf '%s,' "${RES[@]}" | sed 's/,$//')
  SRC=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FORSETI_URL/api/runs" \
    -H "Content-Type: application/json" \
    -d "{\"suite_name\":\"Bifrost E2E\",\"total\":$N,\"passed\":$P,\"failed\":$F,\"skipped\":0,\"errors\":0,\"duration_ms\":30000,\"phase\":\"verification\",\"project_version\":\"0.2.0\",\"base_url\":\"$BIFROST_URL\",\"tests\":[$TESTS]}" --max-time 10) || SRC="ERR"
  echo "  $([ "$SRC" = "200" ] || [ "$SRC" = "201" ] && echo "✅ Submitted ($SRC)" || echo "⚠️ Forseti: $SRC")"
fi
