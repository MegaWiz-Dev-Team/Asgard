#!/bin/bash

# 🚀 Asgard Platform — Master Deployment Script
# One-command deploy all services (K8s + Heimdall)

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASGARD_ROOT="$(dirname "$SCRIPT_DIR")"
HEIMDALL_ROOT="$(dirname "$ASGARD_ROOT")/Heimdall"

# Configuration
SKIP_K8S="${SKIP_K8S:-false}"
SKIP_HEIMDALL="${SKIP_HEIMDALL:-false}"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         🚀 Asgard Platform — Master Deploy                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo "Configuration:"
echo "  Skip K8s:        $SKIP_K8S"
echo "  Skip Heimdall:   $SKIP_HEIMDALL"
echo ""

# ─────────────────────────────────────────────────────────────
# STEP 1: Deploy K8s Services
# ─────────────────────────────────────────────────────────────

if [ "$SKIP_K8S" != "true" ]; then
  echo -e "${YELLOW}[Step 1/2]${NC} Deploying K8s Services..."
  echo "────────────────────────────────────────────────────────────"

  if [ -f "$SCRIPT_DIR/k3s-deploy.sh" ]; then
    bash "$SCRIPT_DIR/k3s-deploy.sh"
  else
    echo -e "${RED}❌ k3s-deploy.sh not found${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ K8s deployment complete${NC}"
  echo ""
else
  echo -e "${YELLOW}[Step 1/2]${NC} Skipping K8s (SKIP_K8S=true)"
  echo ""
fi

# ─────────────────────────────────────────────────────────────
# STEP 2: Deploy Heimdall Services
# ─────────────────────────────────────────────────────────────

if [ "$SKIP_HEIMDALL" != "true" ]; then
  echo -e "${YELLOW}[Step 2/2]${NC} Deploying Heimdall Services..."
  echo "────────────────────────────────────────────────────────────"

  if [ -f "$HEIMDALL_ROOT/scripts/quick-setup.sh" ]; then
    cd "$HEIMDALL_ROOT"
    bash scripts/quick-setup.sh
  else
    echo -e "${RED}❌ Heimdall scripts not found${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Heimdall deployment complete${NC}"
  echo ""
else
  echo -e "${YELLOW}[Step 2/2]${NC} Skipping Heimdall (SKIP_HEIMDALL=true)"
  echo ""
fi

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$SKIP_K8S" != "true" ]; then
  echo "K8s Status:"
  kubectl get pods -n asgard | head -8
  echo ""
fi

echo "📖 Documentation: DEPLOYMENT.md"
