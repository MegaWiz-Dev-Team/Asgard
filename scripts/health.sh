#!/bin/bash
# 🏰 Asgard — Health Check All Services
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS=0
FAIL=0

check() {
    local name="$1"
    local url="$2"
    if curl -sf --max-time 3 "$url" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ $name${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ $name${NC} ($url)"
        FAIL=$((FAIL + 1))
    fi
}

check_docker() {
    local name="$1"
    local container="$2"
    if docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null | grep -q "healthy"; then
        echo -e "  ${GREEN}✅ $name${NC} (healthy)"
        PASS=$((PASS + 1))
    elif docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "  ${YELLOW}⏳ $name${NC} (running, not yet healthy)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌ $name${NC} (not running)"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "🏰 Asgard Health Check"
echo "═══════════════════════"

echo ""
echo "💾 Infrastructure:"
check_docker "MariaDB" "asgard_mariadb"
check_docker "PostgreSQL" "asgard_postgres"
check "Qdrant" "http://localhost:6333/healthz"
check_docker "Redis" "asgard_redis"
check "Neo4j" "http://localhost:7474"

echo ""
echo "🏗️  Services:"
check "Yggdrasil (Auth)" "http://localhost:8085/debug/healthz"
check "Mimir API" "http://localhost:3000/health"
check "Mimir Dashboard" "http://localhost:3001"
check "Bifrost" "http://localhost:8100/healthz"
check "Fenrir" "http://localhost:8200/healthz"

echo ""
echo "🖥️  Host Services:"
check "Heimdall (LLM)" "http://localhost:8080/health"
check "Embedding" "http://localhost:8001/health"

echo ""
echo "═══════════════════════"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo ""
