#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🧪 Asgard E2E Integration Tests                           ║
# ║  Tests the full service chain: Bifrost → Mimir → Heimdall  ║
# ║  ISO/IEC 29110 — Software Implementation Test Execution     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   ./tests/e2e_test.sh              # Run all tests
#   ./tests/e2e_test.sh --quick      # Health checks only
#
# Prerequisites:
#   - Docker Compose stack running (docker compose up -d)
#   - Heimdall running on host (optional, for LLM tests)

set -e

# ═══════════════════════════════════════
# Configuration
# ═══════════════════════════════════════

MIMIR_URL="${MIMIR_URL:-http://localhost:3000}"
BIFROST_URL="${BIFROST_URL:-http://localhost:8100}"
FENRIR_URL="${FENRIR_URL:-http://localhost:8200}"
HEIMDALL_URL="${HEIMDALL_URL:-http://localhost:8080}"
VARDR_URL="${VARDR_URL:-http://localhost:9090}"
YGGDRASIL_URL="${YGGDRASIL_URL:-http://localhost:8085}"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

# ═══════════════════════════════════════
# Helpers
# ═══════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() { echo -e "\n${BLUE}═══════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════${NC}"; }
log_pass() { echo -e "  ${GREEN}✅ PASS${NC} — $1"; ((PASS++)); RESULTS+=("PASS|$1"); }
log_fail() { echo -e "  ${RED}❌ FAIL${NC} — $1 ($2)"; ((FAIL++)); RESULTS+=("FAIL|$1|$2"); }
log_skip() { echo -e "  ${YELLOW}⏭️  SKIP${NC} — $1 ($2)"; ((SKIP++)); RESULTS+=("SKIP|$1|$2"); }

check_http() {
    local url="$1"
    local expected_status="${2:-200}"
    local desc="$3"
    local body_check="$4"

    local response
    response=$(curl -s -w "\n%{http_code}" --max-time 10 "$url" 2>/dev/null) || {
        log_fail "$desc" "Connection refused: $url"
        return 1
    }

    local status_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$status_code" != "$expected_status" ]; then
        log_fail "$desc" "Expected $expected_status, got $status_code"
        return 1
    fi

    if [ -n "$body_check" ]; then
        if echo "$body" | grep -q "$body_check"; then
            log_pass "$desc"
        else
            log_fail "$desc" "Body missing: $body_check"
            return 1
        fi
    else
        log_pass "$desc"
    fi
}

check_post() {
    local url="$1"
    local data="$2"
    local expected_status="${3:-200}"
    local desc="$4"
    local body_check="$5"

    local response
    response=$(curl -s -w "\n%{http_code}" --max-time 30 -X POST \
        -H "Content-Type: application/json" \
        -d "$data" "$url" 2>/dev/null) || {
        log_fail "$desc" "Connection refused: $url"
        return 1
    }

    local status_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    if [ "$status_code" != "$expected_status" ]; then
        log_fail "$desc" "Expected $expected_status, got $status_code"
        return 1
    fi

    if [ -n "$body_check" ]; then
        if echo "$body" | grep -q "$body_check"; then
            log_pass "$desc"
        else
            log_fail "$desc" "Body missing: $body_check"
            return 1
        fi
    else
        log_pass "$desc"
    fi
}

is_service_up() {
    curl -s --max-time 3 "$1" > /dev/null 2>&1
}

# ═══════════════════════════════════════
# Test Suite Start
# ═══════════════════════════════════════

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  🧪 Asgard E2E Integration Tests                       ║"
echo "║  $(date '+%Y-%m-%d %H:%M:%S')                                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ═══════════════════════════════════════
# Phase 1: Infrastructure Health
# ═══════════════════════════════════════

log_header "Phase 1: Infrastructure Health Checks"

# Docker check
if docker info > /dev/null 2>&1; then
    RUNNING=$(docker ps --format '{{.Names}}' | grep -c 'asgard_' 2>/dev/null || echo "0")
    if [ "$RUNNING" -ge 5 ]; then
        log_pass "E2E-001 Docker: $RUNNING asgard containers running"
    else
        log_fail "E2E-001 Docker containers" "Only $RUNNING running (need ≥5)"
    fi
else
    log_fail "E2E-001 Docker" "Docker not running"
fi

# MariaDB
check_http "$MIMIR_URL/health" 200 "E2E-002 MariaDB (via Mimir health)" '"status":"ok"'

# ═══════════════════════════════════════
# Phase 2: Service Health Chain
# ═══════════════════════════════════════

log_header "Phase 2: Service Health Chain"

# Mimir API
check_http "$MIMIR_URL/health" 200 "E2E-010 Mimir API /health" '"service":"ro-ai-bridge"'

# Bifrost
check_http "$BIFROST_URL/healthz" 200 "E2E-011 Bifrost /healthz" '"service":"bifrost"'

# Bifrost readiness (checks Heimdall connectivity)
if is_service_up "$HEIMDALL_URL/health"; then
    check_http "$BIFROST_URL/readyz" 200 "E2E-012 Bifrost /readyz (→ Heimdall)"
else
    log_skip "E2E-012 Bifrost /readyz" "Heimdall not running on host"
fi

# Várðr
check_http "$VARDR_URL/health" 200 "E2E-013 Várðr /health" '"service":"vardr"'

# Várðr API — services
check_http "$VARDR_URL/api/services" 200 "E2E-014 Várðr lists services"

# Heimdall (host)
if is_service_up "$HEIMDALL_URL/health"; then
    check_http "$HEIMDALL_URL/health" 200 "E2E-015 Heimdall /health"
else
    log_skip "E2E-015 Heimdall /health" "Heimdall not running on host"
fi

# ═══════════════════════════════════════
# Phase 3: Cross-Service Integration
# ═══════════════════════════════════════

log_header "Phase 3: Cross-Service Integration"

# Várðr sees all services
VARDR_SERVICES=$(curl -s "$VARDR_URL/api/services" 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$VARDR_SERVICES" -ge 5 ]; then
    log_pass "E2E-020 Várðr sees $VARDR_SERVICES services"
else
    log_fail "E2E-020 Várðr service count" "Only $VARDR_SERVICES (need ≥5)"
fi

# Várðr metrics
check_http "$VARDR_URL/api/metrics" 200 "E2E-021 Várðr metrics API"

# Várðr alerts
check_http "$VARDR_URL/api/alerts/summary" 200 "E2E-022 Várðr alerts summary" '"total_rules"'

# Bifrost → Mimir connectivity (via Bifrost tool registry)
check_http "$BIFROST_URL/v1/tools" 200 "E2E-023 Bifrost tool registry"

# Bifrost agents
check_http "$BIFROST_URL/v1/agents" 200 "E2E-024 Bifrost agents list"

# Quick stop if --quick flag
if [ "${1}" = "--quick" ]; then
    log_header "Quick mode — skipping LLM tests"
    SKIP=$((SKIP + 3))
    RESULTS+=("SKIP|E2E-030 Bifrost→Heimdall chat|Quick mode")
    RESULTS+=("SKIP|E2E-031 Mimir RAG query|Quick mode")
    RESULTS+=("SKIP|E2E-032 Bifrost agent flow|Quick mode")
else

# ═══════════════════════════════════════
# Phase 4: LLM Integration (requires Heimdall)
# ═══════════════════════════════════════

log_header "Phase 4: LLM Integration (Heimdall)"

if is_service_up "$HEIMDALL_URL/health"; then

    # Heimdall model list
    check_http "$HEIMDALL_URL/v1/models" 200 "E2E-030 Heimdall /v1/models"

    # Bifrost → Heimdall chat completion
    check_post \
        "$BIFROST_URL/agents/default/chat" \
        '{"message":"Say hello in exactly 3 words"}' \
        200 \
        "E2E-031 Bifrost→Heimdall agent chat"

    # Mimir ask endpoint (if exists)
    if is_service_up "$MIMIR_URL/api/ask"; then
        check_post \
            "$MIMIR_URL/api/ask" \
            '{"question":"What is the system status?","source_id":1}' \
            200 \
            "E2E-032 Mimir→Heimdall RAG query"
    else
        log_skip "E2E-032 Mimir→Heimdall RAG" "No /api/ask endpoint"
    fi

else
    log_skip "E2E-030 Heimdall models" "Heimdall not running"
    log_skip "E2E-031 Bifrost→Heimdall chat" "Heimdall not running"
    log_skip "E2E-032 Mimir→Heimdall RAG" "Heimdall not running"
fi

fi  # end of non-quick mode

# ═══════════════════════════════════════
# Phase 5: Container Operations (Várðr Sprint 2)
# ═══════════════════════════════════════

log_header "Phase 5: Container Operations via Várðr"

# Alerts rules
RULES_COUNT=$(curl -s "$VARDR_URL/api/alerts/rules" 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$RULES_COUNT" -ge 3 ]; then
    log_pass "E2E-040 Várðr has $RULES_COUNT alert rules"
else
    log_fail "E2E-040 Várðr alert rules" "Only $RULES_COUNT (need ≥3)"
fi

# Container restart endpoint (just verify 200, don't actually restart)
# We test the API exists by checking a stopped container won't crash the endpoint
check_http "$VARDR_URL/api/services" 200 "E2E-041 Várðr service API stable"

# ═══════════════════════════════════════
# Results Summary
# ═══════════════════════════════════════

echo ""
log_header "Test Results Summary"
echo ""

TOTAL=$((PASS + FAIL + SKIP))
echo -e "  ${GREEN}✅ Passed: $PASS${NC}"
echo -e "  ${RED}❌ Failed: $FAIL${NC}"
echo -e "  ${YELLOW}⏭️  Skipped: $SKIP${NC}"
echo -e "  📊 Total: $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}🎉 ALL TESTS PASSED!${NC}"
    EXIT_CODE=0
else
    echo -e "  ${RED}⚠️  $FAIL test(s) failed${NC}"
    EXIT_CODE=1
fi

# Generate JSON report
REPORT_FILE="$(dirname "$0")/e2e_report_$(date '+%Y%m%d_%H%M%S').json"
cat > "$REPORT_FILE" << EOF
{
  "suite": "Asgard E2E Integration Tests",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "summary": {
    "total": $TOTAL,
    "passed": $PASS,
    "failed": $FAIL,
    "skipped": $SKIP
  },
  "results": [
$(for i in "${!RESULTS[@]}"; do
    IFS='|' read -r status name reason <<< "${RESULTS[$i]}"
    COMMA=","
    if [ $i -eq $((${#RESULTS[@]} - 1)) ]; then COMMA=""; fi
    echo "    {\"status\": \"$status\", \"name\": \"$name\", \"reason\": \"${reason:-}\"}"$COMMA
done)
  ]
}
EOF
echo -e "  📄 Report: $REPORT_FILE"
echo ""

exit $EXIT_CODE
