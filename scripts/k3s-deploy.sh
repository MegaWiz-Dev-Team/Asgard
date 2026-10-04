#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Project Asgard — K3s Deploy Script
# Usage: ./scripts/k3s-deploy.sh [api|dashboard|bifrost|tyr|portal|all] [--no-build] [--accept-warn] [--dry-run]
#
# Examples:
#   ./scripts/k3s-deploy.sh all          # Build + deploy everything
#   ./scripts/k3s-deploy.sh api          # Build + deploy API only
#   ./scripts/k3s-deploy.sh dashboard    # Build + deploy dashboard only
#   ./scripts/k3s-deploy.sh bifrost      # Build + deploy bifrost only
#   ./scripts/k3s-deploy.sh tyr          # Deploy Týr (Wazuh SIEM)
#   ./scripts/k3s-deploy.sh all --no-build  # Just apply YAML + rollout restart (no rebuild)
#   ./scripts/k3s-deploy.sh api --dry-run   # Run the gates, print every build/apply step
#
# Image strategy: every build gets a DISTINCT tag, <source-sha>-<YYYYmmddHHMMSS>
#   (e.g. asgard-mimir-api:f11e29b-20261004091500). A tag is never overwritten,
#   so the image a deploy replaces still exists and `kubectl rollout undo`
#   brings it back. The manifest's own image line is ignored: the script
#   applies the manifest with the image it just built (or, with --no-build,
#   the image already running), so env/config changes still propagate.
#
# Gates (before any build): asgard-build-guard.sh once, then
#   asgard-deploy-check.sh for each target. FAIL (exit 2) always stops the
#   deploy; WARN (exit 1) stops it unless --accept-warn is given.
# A rollout that does not become ready is undone with `kubectl rollout undo`.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# Appended, not prepended: a caller's PATH (and the test fakes) must win.
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="${DEV_DIR:-$ROOT_DIR/..}"
MIMIR_DIR="$DEV_DIR/Mimir"
NAMESPACE="asgard"
TARGET="${1:-all}"
NO_BUILD=""
ACCEPT_WARN=0
DRY_RUN=0
for arg in "${@:2}"; do
    case "$arg" in
        --no-build)    NO_BUILD="--no-build" ;;
        --accept-warn) ACCEPT_WARN=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done
STAMP="$(date +%Y%m%d%H%M%S)"
DEPLOY_CHECK="${DEPLOY_CHECK:-$ROOT_DIR/scripts/asgard-deploy-check.sh}"
BUILD_GUARD="${BUILD_GUARD:-$ROOT_DIR/scripts/asgard-build-guard.sh}"

info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "${RED}❌ $1${NC}"; exit 1; }
step()  { echo -e "${CYAN}── $1 ──${NC}"; }

# Mutating commands go through run(), so --dry-run prints them instead.
run() {
    if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}

# <image-name>:<sha of the source checkout>-<STAMP>
image_tag() {
    local name="$1" src="$2" sha
    sha=$(git -C "$src" rev-parse --short HEAD 2>/dev/null) || { echo "❌ $src is not a git checkout" >&2; return 1; }
    echo "${name}:${sha}-${STAMP}"
}

# Applies a manifest with its one container image replaced by $2.
apply_with_image() {
    local yaml="$1" image="$2"
    [ "$(grep -c '^[[:space:]]*image:' "$yaml")" = 1 ] || fail "$yaml must have exactly one image: line"
    if [ "$DRY_RUN" = 1 ]; then
        echo "+ kubectl apply -f $yaml  (image: $image)"
        return
    fi
    sed -E "s#^([[:space:]]*image:).*#\1 ${image}#" "$yaml" | kubectl apply -f -
}

current_image() {
    kubectl get deployment "$1" -n "$2" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

# Applies the manifest with the new image (or, with --no-build, the running
# one plus a restart), waits for the rollout, and undoes it if it fails.
roll_out() {
    local deploy="$1" ns="$2" yaml="$3" built="$4" timeout="$5" previous image
    previous=$(current_image "$deploy" "$ns")
    image="${built:-$previous}"
    [ -n "$image" ] || fail "no image for $deploy: nothing built and none running"
    info "$deploy: ${previous:-<none>} → $image"
    [ -n "$previous" ] && info "rollback: kubectl -n $ns set image deployment/$deploy *=$previous"
    apply_with_image "$yaml" "$image"
    [ -z "$built" ] && run kubectl rollout restart "deployment/$deploy" -n "$ns"
    [ "$DRY_RUN" = 1 ] && return
    info "Waiting for rollout..."
    if ! kubectl rollout status "deployment/$deploy" -n "$ns" --timeout="$timeout"; then
        warn "$deploy did not become ready, undoing the rollout"
        kubectl rollout undo "deployment/$deploy" -n "$ns"
        kubectl rollout status "deployment/$deploy" -n "$ns" --timeout="$timeout" || true
        fail "$deploy rolled back to ${previous:-its previous revision}"
    fi
}

# asgard-deploy-check.sh exits 0 OK, 1 WARN, 2 FAIL.
gate() {
    local deploy="$1" ns="$2" repo="$3" mig_dir="$4" rc=0
    NS="$ns" REPO="$repo" MIG_DIR="$mig_dir" "$DEPLOY_CHECK" "$deploy" || rc=$?
    case "$rc" in
        0) ;;
        1) [ "$ACCEPT_WARN" = 1 ] && warn "$deploy: deploy-check WARN accepted (--accept-warn)" \
               || fail "$deploy: deploy-check WARN. Read it, then rerun with --accept-warn if it is safe" ;;
        *) fail "$deploy: deploy-check FAIL (exit $rc), not deploying" ;;
    esac
}

# deploy-check arguments per target: deployment, namespace, source checkout,
# sqlx migrations dir ("" = no sqlx).
gate_target() {
    case "$1" in
        api)       gate mimir-api       "$NAMESPACE" "$MIMIR_DIR" "ro-ai-bridge/mimir-core-ai/migrations" ;;
        dashboard) gate mimir-dashboard "$NAMESPACE" "$MIMIR_DIR" "" ;;
        portal)    gate asgard-portal   "$NAMESPACE" "$ROOT_DIR" "" ;;
        bifrost)   gate bifrost         "$NAMESPACE" "$DEV_DIR/Bifrost" "" ;;
        tyr)       gate hermodr-wazuh   wazuh        "$DEV_DIR/Hermodr" "" ;;
        all)       for t in bifrost tyr api dashboard portal; do gate_target "$t"; done ;;
    esac
}

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

if [ "$NO_BUILD" != "--no-build" ]; then
    step "Deploy gates"
    "$BUILD_GUARD" || fail "asgard-build-guard.sh blocked the build (disk or cluster); FORCE=1 overrides it"
    gate_target "$TARGET"
    ok "Gates passed"
fi

API_IMAGE=""; DASHBOARD_IMAGE=""; BIFROST_IMAGE=""; PORTAL_IMAGE=""; HERMODR_IMAGE=""

# ─── API ────────────────────────────────────────────────────────
build_api() {
    API_IMAGE=$(image_tag asgard-mimir-api "$MIMIR_DIR")
    step "Building $API_IMAGE"
    cd "$MIMIR_DIR"
    run docker build \
        --build-arg CACHEBUST="$(date +%s)" \
        -t "$API_IMAGE" \
        -f ro-ai-bridge/Dockerfile \
        .
    ok "Built $API_IMAGE"
}

deploy_api() {
    step "Deploying mimir-api"
    roll_out mimir-api "$NAMESPACE" "$ROOT_DIR/k8s/02-services/mimir-api/deployment.yaml" "$API_IMAGE" 180s
    [ "$DRY_RUN" = 1 ] || _health_check mimir-api 8080 /healthz
}

# ─── Dashboard ──────────────────────────────────────────────────
build_dashboard() {
    DASHBOARD_IMAGE=$(image_tag asgard-mimir-dashboard "$MIMIR_DIR")
    step "Building $DASHBOARD_IMAGE"

    if [ -z "$NEXT_PUBLIC_API_URL" ]; then
        warn "NEXT_PUBLIC_API_URL not set — using https://api.asgard.internal/api"
        NEXT_PUBLIC_API_URL="https://api.asgard.internal/api"
    fi
    info "API URL baked into dashboard: $NEXT_PUBLIC_API_URL"

    cd "$MIMIR_DIR/ro-ai-dashboard"
    run docker build \
        --build-arg "NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}" \
        -t "$DASHBOARD_IMAGE" \
        .
    ok "Built $DASHBOARD_IMAGE"
}

deploy_dashboard() {
    step "Deploying mimir-dashboard"
    roll_out mimir-dashboard "$NAMESPACE" "$ROOT_DIR/k8s/02-services/mimir-dashboard/deployment.yaml" "$DASHBOARD_IMAGE" 120s
    ok "mimir-dashboard deployed"
}

# ─── Bifrost ────────────────────────────────────────────────────
build_bifrost() {
    BIFROST_IMAGE=$(image_tag asgard-bifrost "$DEV_DIR/Bifrost")
    step "Building $BIFROST_IMAGE"
    cd "$DEV_DIR"
    run docker build \
        -t "$BIFROST_IMAGE" \
        -f Bifrost/Dockerfile \
        .
    ok "Built $BIFROST_IMAGE"
}

deploy_bifrost() {
    step "Deploying bifrost"
    roll_out bifrost "$NAMESPACE" "$ROOT_DIR/k8s/02-services/bifrost/deployment.yaml" "$BIFROST_IMAGE" 120s
    ok "bifrost deployed"
}

# ─── Portal ─────────────────────────────────────────────────────
build_portal() {
    PORTAL_IMAGE=$(image_tag asgard-portal "$ROOT_DIR")
    step "Building $PORTAL_IMAGE"
    cd "$ROOT_DIR/packages/asgard-portal"
    run docker build \
        -t "$PORTAL_IMAGE" \
        .
    ok "Built $PORTAL_IMAGE"
}

deploy_portal() {
    step "Deploying asgard-portal"
    roll_out asgard-portal "$NAMESPACE" "$ROOT_DIR/k8s/02-services/asgard-portal/deployment.yaml" "$PORTAL_IMAGE" 60s
    ok "asgard-portal deployed"
}

# ─── Hermodr (build only — used by tyr) ─────────────────────────
build_hermodr() {
    HERMODR_IMAGE=$(image_tag asgard-hermodr "$DEV_DIR/Hermodr")
    step "Building $HERMODR_IMAGE"
    cd "$DEV_DIR/Hermodr"
    run docker build \
        -t "$HERMODR_IMAGE" \
        .
    ok "Built $HERMODR_IMAGE"
}

# ─── Tyr ────────────────────────────────────────────────────────
deploy_tyr() {
    step "Deploying Týr (Wazuh SIEM) & Hermóðr Bridge"

    step "Syncing Týr config into K3s ConfigMaps"
    if [ "$DRY_RUN" = 1 ]; then
        echo "+ kubectl apply wazuh-custom-rules + wazuh-custom-decoders configmaps from $DEV_DIR/Tyr"
    else
        kubectl create configmap wazuh-custom-rules \
            --from-file="$DEV_DIR/Tyr/rules/" \
            -n wazuh --dry-run=client -o yaml | kubectl apply -f -
        kubectl create configmap wazuh-custom-decoders \
            --from-file="$DEV_DIR/Tyr/decoders/" \
            -n wazuh --dry-run=client -o yaml | kubectl apply -f -
    fi

    local bridge="$ROOT_DIR/k8s/04-security/tyr/05-hermodr-bridge.yaml" f
    local image="${HERMODR_IMAGE:-$(current_image hermodr-wazuh wazuh)}"
    [ -n "$image" ] || fail "no hermodr image: nothing built and none running"
    for f in "$ROOT_DIR"/k8s/04-security/tyr/*.yaml; do
        if [ "$f" = "$bridge" ]; then apply_with_image "$f" "$image"; else run kubectl apply -f "$f"; fi
    done
    [ -z "$HERMODR_IMAGE" ] && run kubectl rollout restart deployment/hermodr-wazuh -n wazuh
    [ "$DRY_RUN" = 1 ] && return

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
        fail "Unknown target: '$TARGET' (valid: api, dashboard, portal, bifrost, tyr, all)"
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
    -l "app in (mimir-api,mimir-dashboard,bifrost,asgard-portal)" \
    --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
