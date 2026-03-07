#!/usr/bin/env bash
set -euo pipefail

# ============================================
# 🏰 Asgard AI Platform — Stop All Services
# ============================================
# Stops all services in reverse dependency order:
#   Phase 3: Application (Mimir Backend + Dashboard)
#   Phase 2: LLM Backends (Heimdall + MLX)
#   Phase 1: Infrastructure (Docker containers)
#
# Usage:
#   ./scripts/stop.sh              # Stop all
#   ./scripts/stop.sh mimir        # Mimir only
#   ./scripts/stop.sh heimdall     # Heimdall only
#   ./scripts/stop.sh infra        # Infrastructure only
# ============================================

# ── Configuration ─────────────────────────────────────────────────
BASE_DIR="${ASGARD_BASE:-$HOME/Developer}"
MIMIR_DIR="$BASE_DIR/Mimir"
HEIMDALL_DIR="$BASE_DIR/Heimdall"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }

# ── Phase 3: Stop Mimir ──────────────────────────────────────────
stop_mimir() {
    echo ""
    echo -e "${CYAN}━━━ Stopping Mimir ━━━${NC}"

    # Stop Dashboard
    if [ -f "$MIMIR_DIR/.pids/dashboard.pid" ]; then
        local pid=$(cat "$MIMIR_DIR/.pids/dashboard.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            ok "Dashboard stopped (PID $pid)"
        fi
        rm -f "$MIMIR_DIR/.pids/dashboard.pid"
    else
        local pid=$(lsof -ti:3001 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            ok "Dashboard stopped (PID $pid)"
        else
            info "Dashboard not running"
        fi
    fi

    # Stop Backend
    if [ -f "$MIMIR_DIR/.pids/backend.pid" ]; then
        local pid=$(cat "$MIMIR_DIR/.pids/backend.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            ok "Mimir API stopped (PID $pid)"
        fi
        rm -f "$MIMIR_DIR/.pids/backend.pid"
    else
        local pid=$(lsof -ti:3000 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            ok "Mimir API stopped (PID $pid)"
        else
            info "Mimir API not running"
        fi
    fi
}

# ── Phase 2: Stop Heimdall ────────────────────────────────────────
stop_heimdall() {
    echo ""
    echo -e "${CYAN}━━━ Stopping Heimdall ━━━${NC}"

    if [ -f "$HEIMDALL_DIR/scripts/stop.sh" ]; then
        (cd "$HEIMDALL_DIR" && ./scripts/stop.sh 2>/dev/null || true)
        ok "Heimdall stopped"
    else
        warn "Heimdall stop script not found"
        local pid=$(lsof -ti:8080 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            ok "Heimdall Gateway stopped (PID $pid)"
        fi
    fi
}

# ── Phase 1: Stop Infrastructure ─────────────────────────────────
stop_infra() {
    echo ""
    echo -e "${CYAN}━━━ Stopping Infrastructure ━━━${NC}"

    if [ -d "$MIMIR_DIR" ]; then
        (cd "$MIMIR_DIR" && docker compose down 2>&1)
        ok "Docker containers stopped"
    else
        warn "Mimir directory not found: $MIMIR_DIR"
    fi
}

# ── Main ──────────────────────────────────────────────────────────
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🏰 Asgard AI Platform — Stop           ║${NC}"
echo -e "${CYAN}║   Base: $BASE_DIR${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"

case "${1:-all}" in
    mimir|app)
        stop_mimir
        ;;
    heimdall|llm)
        stop_heimdall
        ;;
    infra|infrastructure)
        stop_infra
        ;;
    all|"")
        stop_mimir
        stop_heimdall
        stop_infra
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║   ✅ All Asgard Services Stopped          ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
        echo ""
        ;;
    *)
        echo "Usage: $0 [all|mimir|heimdall|infra]"
        exit 1
        ;;
esac
