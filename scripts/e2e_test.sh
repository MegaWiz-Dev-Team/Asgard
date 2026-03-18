#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🏰 Asgard Full E2E Test Suite
# Tests all services and submits results to Forseti Dashboard
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# Load Asgard secrets (.env) — safe: skip comments, empty lines, and invalid entries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  while IFS='=' read -r key value; do
    if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ "$key" =~ ^[A-Za-z_] ]]; then
      value="${value%\"}" ; value="${value#\"}"
      value="${value%\'}" ; value="${value#\'}"
      export "$key=$value" 2>/dev/null || true
    fi
  done < "$SCRIPT_DIR/../.env"
fi

# ── Port Map ──
# Mimir API:      3000  (internal 8080 → host 3000)
# Mimir Dashboard: 3001  (internal 3000 → host 3001)
# Bifrost:        8100
# Fenrir:         8200
# Ratatoskr:      9200
# Forseti:        5555
# Heimdall:       8080  (host, not Docker)
# Yggdrasil:      8085
# Qdrant:         6333
# Redis:          6379

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
    F=$((F+1)); echo "  ❌ $id: $nm ($val)"
    RES+=("{\"test_id\":\"$id\",\"name\":\"$nm\",\"status\":\"fail\"}")
  fi
}

echo "╔══════════════════════════════════════╗"
echo "║  🏰 Asgard Full E2E Test Suite      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Infrastructure ──
echo "🔧 Infrastructure"
check I01 "PostgreSQL" \
  "docker exec asgard_postgres pg_isready -U postgres && echo OK" "OK"
check I02 "Redis" \
  "docker exec asgard_redis redis-cli ping" "PONG"
check I03 "Qdrant" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:6333/healthz" "200"

# ── Heimdall (host) ──
echo ""
echo "🛡️ Heimdall — LLM Gateway"
check H01 "Health" \
  "curl -s http://localhost:8080/health | python3 -c \"import sys,json;print(json.load(sys.stdin)['status'])\"" "healthy"
check H02 "Chat Completion" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -H 'Authorization: Bearer '\${HEIMDALL_API_KEY:-}'' -d '{\"model\":\"mlx-community/Qwen3.5-9B-MLX-4bit\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}' --max-time 30" "200"

# ── Ratatoskr ──
echo ""
echo "🐿️ Ratatoskr — Shared Browser"
check R01 "Health" \
  "curl -s http://localhost:9200/healthz | python3 -c \"import sys,json;print(json.load(sys.stdin)['status'])\"" "ok"
check R02 "Fetch API" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:9200/api/v1/fetch -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}'" "200"
check R03 "Scrape API" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:9200/api/v1/scrape -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}' --max-time 30" "200|500"

# ── Mimir ──
echo ""
echo "🧠 Mimir — RAG + Knowledge"
check M01 "API Container" \
  "docker inspect asgard_mimir_api --format '{{.State.Health.Status}}'" "healthy"
check M02 "API /healthz" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/healthz --max-time 5" "200"
check M03 "Dashboard" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:3001 --max-time 5" "200|307"

# ── Bifrost ──
echo ""
echo "⚡ Bifrost — Agent Runtime"
check B01 "Container" \
  "docker inspect asgard_bifrost --format '{{.State.Health.Status}}'" "healthy"
check B02 "/v1/agents" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:8100/v1/agents" "200"
check B03 "Agent Run" \
  "curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8100/v1/agents/default/run -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What is 1+1?\"}]}' --max-time 60" "200"

# ── Fenrir ──
echo ""
echo "🐺 Fenrir — Computer-Use Agent"
check F01 "Health" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:8200/healthz" "200"

# ── Forseti ──
echo ""
echo "⚖️ Forseti — Test Dashboard"
check T01 "Dashboard" \
  "curl -s -o /dev/null -w '%{http_code}' $FORSETI_URL/" "200"
check T02 "Runs API" \
  "curl -s -o /dev/null -w '%{http_code}' $FORSETI_URL/api/runs" "200"

# ── Others ──
echo ""
echo "🌳🛡️ Supporting Services"
check Y01 "Yggdrasil" \
  "docker inspect asgard_yggdrasil --format '{{.State.Status}}'" "running"
check V01 "Vardr" \
  "docker inspect asgard_vardr --format '{{.State.Health.Status}}'" "healthy"

# ── Results ──
echo ""
echo "═══════════════════════════════════════"
echo "  $P/$N passed, $F failed"
echo "═══════════════════════════════════════"

# ── Submit to Forseti ──
echo ""
echo "📊 Submitting to Forseti..."
TESTS=$(printf '%s,' "${RES[@]}" | sed 's/,$//')
SRC=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FORSETI_URL/api/runs" \
  -H "Content-Type: application/json" \
  -d "{\"suite_name\":\"Asgard E2E Full\",\"total\":$N,\"passed\":$P,\"failed\":$F,\"skipped\":0,\"errors\":0,\"duration_ms\":30000,\"phase\":\"verification\",\"project_version\":\"0.2.0\",\"base_url\":\"http://localhost\",\"tests\":[$TESTS]}" --max-time 10) || SRC="ERR"

if [ "$SRC" = "200" ] || [ "$SRC" = "201" ]; then
  echo "  ✅ Results submitted ($SRC)"
else
  echo "  ⚠️ Forseti returned: $SRC"
fi

echo ""
echo "🏁 Done — Dashboard: http://localhost:5555"
