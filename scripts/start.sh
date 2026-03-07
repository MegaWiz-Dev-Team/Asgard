#!/usr/bin/env bash
set -euo pipefail

# ============================================
# 🏰 Asgard AI Platform — Start All Services
# ============================================
# Starts all services in the correct dependency order:
#   Phase 1: Infrastructure (Docker containers)
#   Phase 2: LLM Backends (Heimdall + MLX)
#   Phase 3: Application (Mimir Backend + Dashboard)
#
# Usage:
#   ./scripts/start.sh              # Start all
#   ./scripts/start.sh infra        # Infrastructure only
#   ./scripts/start.sh heimdall     # Heimdall only
#   ./scripts/start.sh mimir        # Mimir only
#   ./scripts/start.sh --status     # Check status
# ============================================

# ── Configuration ─────────────────────────────────────────────────
BASE_DIR="${ASGARD_BASE:-$HOME/Documents}"
MIMIR_DIR="$BASE_DIR/Mimir"
HEIMDALL_DIR="$BASE_DIR/Heimdall"

# Port assignments (Asgard architecture design)
MIMIR_API_PORT=3000
DASHBOARD_PORT=3001
HEIMDALL_PORT=8080
EMBEDDING_PORT=8001
VAULT_PORT=8201

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }

# ── Status Check ──────────────────────────────────────────────────
check_status() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🏰 Asgard Platform — Status            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Infrastructure
    echo -e "${BLUE}── Phase 1: Infrastructure ──${NC}"
    local services=("mimir_mariadb:3306" "mimir_qdrant:6333" "mimir_redis:6379" "mimir_vault:$VAULT_PORT" "mimir_rustfs:9000" "mimir_neo4j:7474")
    for svc in "${services[@]}"; do
        local name="${svc%%:*}"
        local port="${svc##*:}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$name"; then
            ok "$name (:$port)"
        else
            err "$name (:$port)"
        fi
    done

    echo ""
    echo -e "${BLUE}── Phase 2: LLM Backends ──${NC}"
    if curl -sf http://localhost:$HEIMDALL_PORT/health >/dev/null 2>&1; then
        ok "Heimdall Gateway (:$HEIMDALL_PORT)"
    else
        err "Heimdall Gateway (:$HEIMDALL_PORT)"
    fi
    if curl -sf http://localhost:$EMBEDDING_PORT/health >/dev/null 2>&1; then
        ok "Embedding Server (:$EMBEDDING_PORT)"
    else
        err "Embedding Server (:$EMBEDDING_PORT)"
    fi

    echo ""
    echo -e "${BLUE}── Phase 3: Application ──${NC}"
    if curl -sf http://localhost:$MIMIR_API_PORT/health >/dev/null 2>&1; then
        ok "Mimir API (:$MIMIR_API_PORT)"
    else
        err "Mimir API (:$MIMIR_API_PORT)"
    fi
    if curl -sf http://localhost:$DASHBOARD_PORT >/dev/null 2>&1; then
        ok "Dashboard (:$DASHBOARD_PORT)"
    else
        err "Dashboard (:$DASHBOARD_PORT)"
    fi
    echo ""
}

# ── Phase 1: Infrastructure ───────────────────────────────────────
start_infra() {
    echo ""
    echo -e "${CYAN}━━━ Phase 1: Infrastructure ━━━${NC}"

    if [ ! -d "$MIMIR_DIR" ]; then
        err "Mimir directory not found: $MIMIR_DIR"
        err "Set ASGARD_BASE to the parent directory of Mimir/Heimdall"
        exit 1
    fi

    info "Starting Docker containers..."
    (cd "$MIMIR_DIR" && docker compose up -d 2>&1)

    # Wait for MariaDB
    info "Waiting for MariaDB..."
    for i in $(seq 1 30); do
        if docker exec mimir_mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
            ok "MariaDB healthy"
            break
        fi
        [ "$i" -eq 30 ] && warn "MariaDB not ready after 30s"
        sleep 2
    done

    # Wait for Vault
    info "Waiting for Vault..."
    for i in $(seq 1 15); do
        if curl -sf http://localhost:$VAULT_PORT/v1/sys/health >/dev/null 2>&1; then
            ok "Vault healthy"
            break
        fi
        [ "$i" -eq 15 ] && warn "Vault not ready after 15s"
        sleep 2
    done

    ok "Infrastructure ready"
}

# ── Phase 2: Heimdall ─────────────────────────────────────────────
start_heimdall() {
    echo ""
    echo -e "${CYAN}━━━ Phase 2: LLM Backends (Heimdall) ━━━${NC}"

    if [ ! -d "$HEIMDALL_DIR" ]; then
        err "Heimdall directory not found: $HEIMDALL_DIR"
        err "Set ASGARD_BASE to the parent directory of Mimir/Heimdall"
        exit 1
    fi

    # Check if already running
    if curl -sf http://localhost:$HEIMDALL_PORT/health >/dev/null 2>&1; then
        ok "Heimdall already running on :$HEIMDALL_PORT"
        return
    fi

    info "Starting Heimdall..."
    (cd "$HEIMDALL_DIR" && ./scripts/start.sh)

    ok "Heimdall ready on :$HEIMDALL_PORT"
}

# ── Phase 3: Mimir ────────────────────────────────────────────────
start_mimir() {
    echo ""
    echo -e "${CYAN}━━━ Phase 3: Application (Mimir) ━━━${NC}"

    mkdir -p "$MIMIR_DIR/logs" "$MIMIR_DIR/.pids"

    # Backend
    if curl -sf http://localhost:$MIMIR_API_PORT/health >/dev/null 2>&1; then
        ok "Mimir API already running on :$MIMIR_API_PORT"
    else
        local backend_bin="$MIMIR_DIR/target/release/ro-ai-bridge"
        if [ ! -f "$backend_bin" ]; then
            info "Backend not built. Building release..."
            (cd "$MIMIR_DIR/ro-ai-bridge" && cargo build --release 2>&1 | tail -1)
        fi

        info "Starting Mimir API on :$MIMIR_API_PORT..."
        cd "$MIMIR_DIR/ro-ai-bridge"
        nohup "$backend_bin" > "$MIMIR_DIR/logs/backend.log" 2>&1 &
        local backend_pid=$!
        echo "$backend_pid" > "$MIMIR_DIR/.pids/backend.pid"

        # Wait for API
        for i in $(seq 1 15); do
            if curl -sf http://localhost:$MIMIR_API_PORT/health >/dev/null 2>&1; then
                ok "Mimir API ready (PID $backend_pid)"
                break
            fi
            [ "$i" -eq 15 ] && warn "API not ready after 15s — check logs/backend.log"
            sleep 2
        done
    fi

    # Dashboard
    if curl -sf http://localhost:$DASHBOARD_PORT >/dev/null 2>&1; then
        ok "Dashboard already running on :$DASHBOARD_PORT"
    else
        info "Starting Dashboard on :$DASHBOARD_PORT..."
        cd "$MIMIR_DIR/ro-ai-dashboard"
        nohup npm start > "$MIMIR_DIR/logs/dashboard.log" 2>&1 &
        local dash_pid=$!
        echo "$dash_pid" > "$MIMIR_DIR/.pids/dashboard.pid"

        for i in $(seq 1 15); do
            if curl -sf http://localhost:$DASHBOARD_PORT >/dev/null 2>&1; then
                ok "Dashboard ready (PID $dash_pid)"
                break
            fi
            [ "$i" -eq 15 ] && warn "Dashboard not ready after 15s — check logs/dashboard.log"
            sleep 2
        done
    fi
}

# ── Main ──────────────────────────────────────────────────────────
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🏰 Asgard AI Platform — Start          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"

case "${1:-all}" in
    --status|-s)
        check_status
        ;;
    infra|infrastructure)
        start_infra
        echo ""
        ok "Infrastructure started. Next: ./scripts/start.sh heimdall"
        ;;
    heimdall|llm)
        start_heimdall
        echo ""
        ok "Heimdall started. Next: ./scripts/start.sh mimir"
        ;;
    mimir|app)
        start_mimir
        echo ""
        ok "Mimir started."
        ;;
    all|"")
        start_infra
        start_heimdall
        start_mimir
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║   ✅ All Asgard Services Running!         ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo "  🧠 Mimir API:     http://localhost:$MIMIR_API_PORT"
        echo "  🖥️  Dashboard:     http://localhost:$DASHBOARD_PORT"
        echo "  🛡️  Heimdall:      http://localhost:$HEIMDALL_PORT"
        echo "  🔐 Vault UI:      http://localhost:$VAULT_PORT"
        echo "  🔗 Neo4j:         http://localhost:7474"
        echo ""
        ;;
    *)
        echo "Usage: $0 [all|infra|heimdall|mimir|--status]"
        exit 1
        ;;
esac
