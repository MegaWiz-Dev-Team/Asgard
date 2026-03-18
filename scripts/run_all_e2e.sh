#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 🏰 Asgard — Run All E2E Tests
# Master script that runs every service's E2E suite
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$SCRIPT_DIR/e2e"

# Load Asgard secrets
if [ -f "$SCRIPT_DIR/../.env" ]; then
  while IFS='=' read -r key value; do
    if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ "$key" =~ ^[A-Za-z_] ]]; then
      value="${value%\"}" ; value="${value#\"}"
      value="${value%\'}" ; value="${value#\'}"
      export "$key=$value" 2>/dev/null || true
    fi
  done < "$SCRIPT_DIR/../.env"
fi

# Available suites
SUITES=(asgard bifrost ratatoskr fenrir forseti huginn muninn eir vardr)

# Parse args — run specific suites or all
if [ $# -gt 0 ]; then
  SUITES=("$@")
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🏰 Asgard — E2E Test Runner                ║"
echo "║  Running: ${SUITES[*]}  "
echo "╚══════════════════════════════════════════════╝"
echo ""

TOTAL_P=0; TOTAL_F=0; TOTAL_N=0
RESULTS=()

for suite in "${SUITES[@]}"; do
  script="$E2E_DIR/${suite}.sh"
  if [ ! -f "$script" ]; then
    echo "⚠️  Script not found: $script"
    continue
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  # Run the suite and capture output
  bash "$script" 2>&1
  echo ""
done

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🏁 All E2E Suites Complete                  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Usage:"
echo "  Run all:       bash scripts/run_all_e2e.sh"
echo "  Run specific:  bash scripts/run_all_e2e.sh bifrost ratatoskr"
echo "  Dashboard:     http://localhost:5555"
