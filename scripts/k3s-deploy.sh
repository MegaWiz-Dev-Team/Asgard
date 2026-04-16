#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Project Mimir — K3s Deploy Script
# Usage: ./scripts/k3s-deploy.sh [api|dashboard|all] [--no-build]
#
# Examples:
#   ./scripts/k3s-deploy.sh all          # Build + deploy everything
#   ./scripts/k3s-deploy.sh api          # Build + deploy API only
#   ./scripts/k3s-deploy.sh dashboard    # Build + deploy dashboard only
#   ./scripts/k3s-deploy.sh bifrost      # Build + deploy bifrost only
#   ./scripts/k3s-deploy.sh tyr          # Deploy Týr (Wazuh SIEM)
#   ./scripts/k3s-deploy.sh all --no-build  # Just rollout restart (no rebuild)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# Ensure standard OrbStack and Homebrew binary paths are available
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE="asgard"
TARGET="${1:-all}"
NO_BUILD="${2:-}"

info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "${RED}❌ $1${NC}"; exit 1; }
step()  { echo -e "${CYAN}── $1 ──${NC}"; }

# ─── Generate image tag from git short hash + timestamp ──────────
GIT_SHA=$(cd "$ROOT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "dev")
TIMESTAMP=$(date +%Y%m%d%H%M%S)
TAG="${GIT_SHA}-${TIMESTAMP}"

# ─── Configuration ───────────────────────────────────────────────
# Override these via environment variables if needed:
NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-https://api.asgard.internal/api}"
NEXT_PUBLIC_YGGDRASIL_CLIENT_ID="${NEXT_PUBLIC_YGGDRASIL_CLIENT_ID:-}"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   🏰 Asgard — K3s Master Deploy             ║"
echo "║   Target:    $(printf '%-33s' "$TARGET")║"
echo "║   Tag:       $(printf '%-33s' "$TAG")║"
echo "║   Namespace: $(printf '%-33s' "$NAMESPACE")║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ─── Preflight checks ───────────────────────────────────────────
step "Preflight checks"
command -v docker  >/dev/null 2>&1 || fail "Docker is not installed"
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
kubectl cluster-info >/dev/null 2>&1 || fail "Cannot connect to Kubernetes cluster"
ok "Preflight OK"

# ─── Build & Deploy API ─────────────────────────────────────────
build_api() {
    step "Building mimir-api:${TAG}"
    cd "$ROOT_DIR/../Mimir"
    docker build \
        --build-arg CACHEBUST="$TIMESTAMP" \
        -t "mimir-api:${TAG}" \
        -f ro-ai-bridge/Dockerfile \
        .
    ok "Built mimir-api:${TAG}"
}

deploy_api() {
    step "Deploying mimir-api"
    if [ "$NO_BUILD" != "--no-build" ]; then
        kubectl set image "deployment/mimir-api" \
            "mimir-api=mimir-api:${TAG}" \
            -n "$NAMESPACE"
    else
        kubectl rollout restart "deployment/mimir-api" -n "$NAMESPACE"
    fi
    
    info "Waiting for rollout..."
    kubectl rollout status "deployment/mimir-api" \
        -n "$NAMESPACE" \
        --timeout=120s
    
    # Verify health
    sleep 3
    local health
    health=$(kubectl exec "deployment/mimir-api" -n "$NAMESPACE" -- \
        curl -sf http://localhost:8080/health 2>/dev/null || echo '{"status":"error"}')
    
    if echo "$health" | grep -q '"ok"'; then
        ok "mimir-api healthy: $health"
    else
        warn "mimir-api health check returned: $health"
    fi
}

# ─── Build & Deploy Bifrost ─────────────────────────────────────
build_bifrost() {
    step "Building asgard-bifrost:${TAG}"
    cd "$ROOT_DIR/.."
    docker build \
        -t "asgard-bifrost:${TAG}" \
        -f Bifrost/Dockerfile \
        .
    ok "Built asgard-bifrost:${TAG}"
}

deploy_bifrost() {
    step "Deploying bifrost"
    if [ "$NO_BUILD" != "--no-build" ]; then
        kubectl set image "deployment/bifrost" \
            "bifrost=asgard-bifrost:${TAG}" \
            -n "$NAMESPACE"
    else
        kubectl rollout restart "deployment/bifrost" -n "$NAMESPACE"
    fi
    
    info "Waiting for rollout..."
    kubectl rollout status "deployment/bifrost" \
        -n "$NAMESPACE" \
        --timeout=120s
    ok "bifrost deployed"
}

# ─── Build Hermodr ──────────────────────────────────────────────
build_hermodr() {
    step "Building asgard-hermodr:${TAG}"
    cd "$ROOT_DIR/../Hermodr"
    docker build \
        -t "asgard-hermodr:${TAG}" \
        .
    ok "Built asgard-hermodr:${TAG}"
}

# ─── Build & Deploy Dashboard ───────────────────────────────────
build_dashboard() {
    step "Building mimir-dashboard:${TAG}"
    
    cd "$ROOT_DIR/../Mimir/ro-ai-dashboard"
    
    # Validate build args
    if [ -z "$NEXT_PUBLIC_API_URL" ]; then
        warn "NEXT_PUBLIC_API_URL not set — defaulting to https://api.asgard.internal/api"
        NEXT_PUBLIC_API_URL="https://api.asgard.internal/api"
    fi
    info "API URL baked into dashboard: $NEXT_PUBLIC_API_URL"
    
    docker build \
        --build-arg "NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}" \
        -t "mimir-dashboard:${TAG}" \
        .
    ok "Built mimir-dashboard:${TAG}"
}

deploy_dashboard() {
    step "Deploying mimir-dashboard"
    if [ "$NO_BUILD" != "--no-build" ]; then
        kubectl set image "deployment/mimir-dashboard" \
            "mimir-dashboard=mimir-dashboard:${TAG}" \
            -n "$NAMESPACE"
    else
        kubectl rollout restart "deployment/mimir-dashboard" -n "$NAMESPACE"
    fi
    
    info "Waiting for rollout..."
    kubectl rollout status "deployment/mimir-dashboard" \
        -n "$NAMESPACE" \
        --timeout=120s
    ok "mimir-dashboard deployed"
}

# ─── Build & Deploy Portal ──────────────────────────────────────
build_portal() {
    step "Building asgard-portal:${TAG}"
    cd "$ROOT_DIR/packages/asgard-portal"
    docker build \
        -t "asgard-portal:${TAG}" \
        .
    ok "Built asgard-portal:${TAG}"
}

deploy_portal() {
    step "Deploying asgard-portal"
    # Apply the deployment YAML if it doesn't exist, to ensure it's created
    kubectl apply -f "$ROOT_DIR/k8s/02-services/asgard-portal/deployment.yaml"
    
    if [ "$NO_BUILD" != "--no-build" ]; then
        kubectl set image "deployment/asgard-portal" \
            "asgard-portal=asgard-portal:${TAG}" \
            -n "asgard"
    else
        kubectl rollout restart "deployment/asgard-portal" -n "asgard"
    fi
    
    info "Waiting for rollout..."
    kubectl rollout status "deployment/asgard-portal" \
        -n "asgard" \
        --timeout=60s
    ok "asgard-portal deployed"
}

# ─── Deploy Tyr ─────────────────────────────────────────────────
deploy_tyr() {
    step "Deploying Týr (Wazuh SIEM) & Hermóðr Bridge"
    
    # Absorb Tyr rules and decoders into ConfigMaps
    step "Syncing Týr configuration into K3s ConfigMaps"
    kubectl create configmap wazuh-custom-rules --from-file="$ROOT_DIR/../Tyr/rules/" -n wazuh --dry-run=client -o yaml | kubectl apply -f -
    kubectl create configmap wazuh-custom-decoders --from-file="$ROOT_DIR/../Tyr/decoders/" -n wazuh --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f "$ROOT_DIR/k8s/04-security/tyr/"
    
    # Fast-rollout Hermodr bridge if deployment exists
    if kubectl get deployment hermodr-wazuh -n wazuh >/dev/null 2>&1; then
        if [ "$NO_BUILD" != "--no-build" ]; then
            kubectl set image deployment/hermodr-wazuh \
                "hermodr=asgard-hermodr:${TAG}" \
                -n wazuh
        else
            kubectl rollout restart deployment/hermodr-wazuh -n wazuh
        fi
    fi
    
    info "Waiting for rollout..."
    kubectl rollout status "statefulset/wazuh-indexer" -n wazuh --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status "deployment/wazuh-manager" -n wazuh --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status "deployment/hermodr-wazuh" -n wazuh --timeout=60s >/dev/null 2>&1 || true
    ok "tyr deployed"
}

# ─── Execute ─────────────────────────────────────────────────────
case "$TARGET" in
    api)
        if [ "$NO_BUILD" != "--no-build" ]; then build_api; fi
        deploy_api
        ;;
    dashboard)
        if [ "$NO_BUILD" != "--no-build" ]; then build_dashboard; fi
        deploy_dashboard
        ;;
    portal)
        if [ "$NO_BUILD" != "--no-build" ]; then build_portal; fi
        deploy_portal
        ;;
    bifrost)
        if [ "$NO_BUILD" != "--no-build" ]; then build_bifrost; fi
        deploy_bifrost
        ;;
    tyr)
        if [ "$NO_BUILD" != "--no-build" ]; then build_hermodr; fi
        deploy_tyr
        ;;
    all)
        if [ "$NO_BUILD" != "--no-build" ]; then
            build_bifrost
            build_hermodr
            build_api
            build_dashboard
            build_portal
        fi
        deploy_bifrost
        deploy_api
        deploy_dashboard
        deploy_portal
        deploy_tyr
        ;;
    *)
        fail "Unknown target: $TARGET (use: api, dashboard, portal, bifrost, tyr, or all)"
        ;;
esac

# ─── Summary ─────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   ✅ Deploy Complete                         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  API:       http://localhost:30000/health"
echo "  Dashboard: http://localhost:30001"
echo ""
echo "  Pods:"
kubectl get pods -A -l "app in (mimir-api,mimir-dashboard,bifrost)" \
    --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
