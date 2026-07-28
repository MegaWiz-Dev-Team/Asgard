#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Project Asgard — K3s Deploy Script
# Usage: ./scripts/k3s-deploy.sh [api|dashboard|bifrost|tyr|portal|nott|all] [--no-build]
#
# Examples:
#   ./scripts/k3s-deploy.sh all          # Build + deploy everything
#   ./scripts/k3s-deploy.sh api          # Build + deploy API only
#   ./scripts/k3s-deploy.sh dashboard    # Build + deploy dashboard only
#   ./scripts/k3s-deploy.sh bifrost      # Build + deploy bifrost only
#   ./scripts/k3s-deploy.sh tyr          # Deploy Týr (Wazuh SIEM)
#   ./scripts/k3s-deploy.sh nott         # Build + deploy Nótt Box edge (+ mosquitto broker)
#   ./scripts/k3s-deploy.sh all --no-build  # Just apply YAML + rollout restart (no rebuild)
#
# Image strategy: builds as :latest (imagePullPolicy: Never in K3s).
#   kubectl apply -f <yaml> propagates env/config changes.
#   rollout restart forces pods to re-pull the new :latest from local store.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIMIR_DIR="$(cd "$ROOT_DIR/../Mimir" && pwd)"
NAMESPACE="asgard"
TARGET="${1:-all}"
NO_BUILD="${2:-}"

info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "${RED}❌ $1${NC}"; exit 1; }
step()  { echo -e "${CYAN}── $1 ──${NC}"; }

GIT_SHA=$(cd "$ROOT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "dev")

NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-https://api.asgard.internal/api}"
NEXT_PUBLIC_YGGDRASIL_CLIENT_ID="${NEXT_PUBLIC_YGGDRASIL_CLIENT_ID:-}"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   🏰 Asgard — K3s Master Deploy             ║"
echo "║   Target:    $(printf '%-33s' "$TARGET")║"
echo "║   Commit:    $(printf '%-33s' "$GIT_SHA")║"
echo "║   Namespace: $(printf '%-33s' "$NAMESPACE")║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ─── Preflight checks ───────────────────────────────────────────
step "Preflight checks"
command -v docker  >/dev/null 2>&1 || fail "Docker is not installed"
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
kubectl cluster-info >/dev/null 2>&1 || fail "Cannot connect to Kubernetes cluster"
ok "Preflight OK"

# ─── API ────────────────────────────────────────────────────────
build_api() {
    step "Building asgard-mimir-api:latest (commit: $GIT_SHA)"
    cd "$MIMIR_DIR"
    docker build \
        --build-arg CACHEBUST="$(date +%s)" \
        -t "asgard-mimir-api:latest" \
        -f ro-ai-bridge/Dockerfile \
        .
    ok "Built asgard-mimir-api:latest"
}

deploy_api() {
    step "Deploying mimir-api"
    kubectl apply -f "$ROOT_DIR/k8s/02-services/mimir-api/deployment.yaml"
    kubectl rollout restart deployment/mimir-api -n "$NAMESPACE"
    info "Waiting for rollout..."
    kubectl rollout status deployment/mimir-api -n "$NAMESPACE" --timeout=180s
    _health_check mimir-api 8080 /healthz
}

# ─── Dashboard ──────────────────────────────────────────────────
build_dashboard() {
    step "Building asgard-mimir-dashboard:latest"

    if [ -z "$NEXT_PUBLIC_API_URL" ]; then
        warn "NEXT_PUBLIC_API_URL not set — using https://api.asgard.internal/api"
        NEXT_PUBLIC_API_URL="https://api.asgard.internal/api"
    fi
    info "API URL baked into dashboard: $NEXT_PUBLIC_API_URL"

    cd "$MIMIR_DIR/ro-ai-dashboard"
    docker build \
        --build-arg "NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}" \
        -t "asgard-mimir-dashboard:latest" \
        .
    ok "Built asgard-mimir-dashboard:latest"
}

deploy_dashboard() {
    step "Deploying mimir-dashboard"
    kubectl apply -f "$ROOT_DIR/k8s/02-services/mimir-dashboard/deployment.yaml"
    kubectl rollout restart deployment/mimir-dashboard -n "$NAMESPACE"
    info "Waiting for rollout..."
    kubectl rollout status deployment/mimir-dashboard -n "$NAMESPACE" --timeout=120s
    ok "mimir-dashboard deployed"
}

# ─── Bifrost ────────────────────────────────────────────────────
build_bifrost() {
    step "Building asgard-bifrost:latest"
    cd "$ROOT_DIR/.."
    docker build \
        -t "asgard-bifrost:latest" \
        -f Bifrost/Dockerfile \
        .
    ok "Built asgard-bifrost:latest"
}

deploy_bifrost() {
    step "Deploying bifrost"
    kubectl apply -f "$ROOT_DIR/k8s/02-services/bifrost/deployment.yaml"
    kubectl rollout restart deployment/bifrost -n "$NAMESPACE"
    info "Waiting for rollout..."
    kubectl rollout status deployment/bifrost -n "$NAMESPACE" --timeout=120s
    ok "bifrost deployed"
}

# ─── Portal ─────────────────────────────────────────────────────
build_portal() {
    step "Building asgard-portal:latest"
    cd "$ROOT_DIR/packages/asgard-portal"
    docker build \
        -t "asgard-portal:latest" \
        .
    ok "Built asgard-portal:latest"
}

deploy_portal() {
    step "Deploying asgard-portal"
    kubectl apply -f "$ROOT_DIR/k8s/02-services/asgard-portal/deployment.yaml"
    kubectl rollout restart deployment/asgard-portal -n "$NAMESPACE"
    info "Waiting for rollout..."
    kubectl rollout status deployment/asgard-portal -n "$NAMESPACE" --timeout=60s
    ok "asgard-portal deployed"
}

# ─── Hermodr (build only — used by tyr) ─────────────────────────
build_hermodr() {
    step "Building asgard-hermodr:latest"
    cd "$ROOT_DIR/../Hermodr"
    docker build \
        -t "asgard-hermodr:latest" \
        .
    ok "Built asgard-hermodr:latest"
}

# ─── Nótt Box edge ──────────────────────────────────────────────
build_nott() {
    step "Building asgard-nott-box-edge:latest"
    cd "$ROOT_DIR/../nott-box"
    docker build \
        -t "asgard-nott-box-edge:latest" \
        .
    ok "Built asgard-nott-box-edge:latest"
}

deploy_nott() {
    step "Deploying mosquitto (broker) + nott-box-edge"
    kubectl apply -f "$ROOT_DIR/k8s/01-infra/mosquitto/deployment.yaml"
    kubectl rollout status deployment/mosquitto -n asgard-infra --timeout=120s
    kubectl apply -f "$ROOT_DIR/k8s/02-services/nott-box-edge/deployment.yaml"
    kubectl rollout restart deployment/nott-box-edge -n "$NAMESPACE"
    info "Waiting for rollout..."
    kubectl rollout status deployment/nott-box-edge -n "$NAMESPACE" --timeout=120s
    _health_check nott-box-edge 8180 /healthz
}

# ─── Tyr ────────────────────────────────────────────────────────
deploy_tyr() {
    step "Deploying Týr (Wazuh SIEM) & Hermóðr Bridge"

    step "Syncing Týr config into K3s ConfigMaps"
    kubectl create configmap wazuh-custom-rules \
        --from-file="$ROOT_DIR/../Tyr/rules/" \
        -n wazuh --dry-run=client -o yaml | kubectl apply -f -
    kubectl create configmap wazuh-custom-decoders \
        --from-file="$ROOT_DIR/../Tyr/decoders/" \
        -n wazuh --dry-run=client -o yaml | kubectl apply -f -

    kubectl apply -f "$ROOT_DIR/k8s/04-security/tyr/"

    if kubectl get deployment hermodr-wazuh -n wazuh >/dev/null 2>&1; then
        kubectl rollout restart deployment/hermodr-wazuh -n wazuh
    fi

    info "Waiting for rollout..."
    kubectl rollout status statefulset/wazuh-indexer -n wazuh --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment/wazuh-manager  -n wazuh --timeout=120s >/dev/null 2>&1 || true
    kubectl rollout status deployment/hermodr-wazuh  -n wazuh --timeout=60s  >/dev/null 2>&1 || true
    ok "tyr deployed"
}

# ─── Health check helper ─────────────────────────────────────────
_health_check() {
    local deployment="$1" port="$2" path="$3"
    sleep 3
    local health
    health=$(kubectl exec "deployment/${deployment}" -n "$NAMESPACE" -- \
        curl -sf "http://localhost:${port}${path}" 2>/dev/null || echo '{"status":"error"}')
    if echo "$health" | grep -qE '"ok"|"healthy"'; then
        ok "${deployment} healthy: ${health}"
    else
        warn "${deployment} health probe returned: ${health}"
    fi
}

# ─── Execute ─────────────────────────────────────────────────────
case "$TARGET" in
    api)
        [ "$NO_BUILD" != "--no-build" ] && build_api
        deploy_api
        ;;
    dashboard)
        [ "$NO_BUILD" != "--no-build" ] && build_dashboard
        deploy_dashboard
        ;;
    portal)
        [ "$NO_BUILD" != "--no-build" ] && build_portal
        deploy_portal
        ;;
    bifrost)
        [ "$NO_BUILD" != "--no-build" ] && build_bifrost
        deploy_bifrost
        ;;
    tyr)
        [ "$NO_BUILD" != "--no-build" ] && build_hermodr
        deploy_tyr
        ;;
    nott)
        [ "$NO_BUILD" != "--no-build" ] && build_nott
        deploy_nott
        ;;
    all)
        if [ "$NO_BUILD" != "--no-build" ]; then
            build_bifrost
            build_hermodr
            build_api
            build_dashboard
            build_portal
            build_nott
        fi
        deploy_bifrost
        deploy_api
        deploy_dashboard
        deploy_portal
        deploy_tyr
        deploy_nott
        ;;
    *)
        fail "Unknown target: '$TARGET' (valid: api, dashboard, portal, bifrost, tyr, nott, all)"
        ;;
esac

# ─── Summary ─────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   ✅ Deploy Complete                         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  API:       http://localhost:30000/healthz"
echo "  Dashboard: http://localhost:30001"
echo ""
echo "  Pods:"
kubectl get pods -n "$NAMESPACE" \
    -l "app in (mimir-api,mimir-dashboard,bifrost,asgard-portal,nott-box-edge)" \
    --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
