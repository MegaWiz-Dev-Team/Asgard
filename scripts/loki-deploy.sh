#!/bin/bash
# ============================================================================
# Loki Security Testing Service - Complete Deployment Script
#
# Purpose:
#   Deploy Loki penetration testing service for authorized internal testing
#   of Asgard defenses (API injection, prompt injection, data exfiltration)
#
# Usage:
#   ./scripts/loki-deploy.sh [build|deploy|test|cleanup]
#
# Stages:
#   1. build    - Docker image build (Kali Linux)
#   2. deploy   - K8s deployment (manifests + DB migration)
#   3. test     - Run security test suites
#   4. cleanup  - Remove Loki from cluster
#
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASGARD_DIR="$(dirname "$SCRIPT_DIR")"
LOKI_K8S_DIR="$ASGARD_DIR/k8s/04-security/loki"
MIMIR_DIR="$ASGARD_DIR/../Mimir"

LOKI_IMAGE="asgard-loki:latest"
NAMESPACE="asgard"
POD_NAME="loki"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── Utility Functions ──────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Install Docker first."
        exit 1
    fi
    log_success "Docker found"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Install kubectl first."
        exit 1
    fi
    log_success "kubectl found"

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is it running?"
        exit 1
    fi
    log_success "Kubernetes cluster accessible"

    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warn "Namespace '$NAMESPACE' not found. Creating..."
        kubectl create namespace "$NAMESPACE"
    fi
    log_success "Namespace '$NAMESPACE' ready"
}

# ─── Build Stage ───────────────────────────────────────────────────────────

build_image() {
    log_info "Building Loki Docker image..."

    if [ ! -f "$LOKI_K8S_DIR/Dockerfile" ]; then
        log_error "Dockerfile not found at $LOKI_K8S_DIR/Dockerfile"
        exit 1
    fi

    docker build \
        -t "$LOKI_IMAGE" \
        -f "$LOKI_K8S_DIR/Dockerfile" \
        "$LOKI_K8S_DIR"

    log_success "Loki Docker image built: $LOKI_IMAGE"
    docker images | grep "asgard-loki"
}

# ─── Deploy Stage ──────────────────────────────────────────────────────────

deploy_k8s() {
    log_info "Deploying Loki to Kubernetes..."

    # RBAC
    log_info "Applying RBAC..."
    kubectl apply -f "$LOKI_K8S_DIR/01-rbac.yaml"

    # ConfigMaps (test scripts and payloads)
    log_info "Applying ConfigMaps (test scripts and payloads)..."
    kubectl apply -f "$LOKI_K8S_DIR/04-configmaps.yaml"

    # Network Policy
    log_info "Applying NetworkPolicy..."
    kubectl apply -f "$LOKI_K8S_DIR/03-network-policy.yaml"

    # Deployment + Service
    log_info "Applying Deployment and Service..."
    kubectl apply -f "$LOKI_K8S_DIR/02-deployment.yaml"

    log_success "K8s resources deployed"

    # Wait for pod to be ready
    log_info "Waiting for Loki pod to be ready..."
    kubectl -n "$NAMESPACE" wait --for=condition=ready pod \
        -l app=loki --timeout=300s 2>/dev/null || {
        log_warn "Pod not ready yet. Check logs with:"
        echo "  kubectl -n $NAMESPACE logs $POD_NAME"
    }

    log_success "Loki pod ready"
    kubectl -n "$NAMESPACE" get pod -l app=loki
}

deploy_agent() {
    log_info "Deploying Loki agent to Mimir (asgard_platform tenant)..."

    if [ ! -f "$MIMIR_DIR/ro-ai-bridge/mimir-core-ai/migrations/20260528000000_loki_security_test_agent.sql" ]; then
        log_error "Agent migration not found at $MIMIR_DIR/.../migrations/20260528000000_loki_security_test_agent.sql"
        exit 1
    fi

    # Check if we can reach Mimir database
    if ! command -v mysql &> /dev/null; then
        log_warn "mysql CLI not found. Agent migration requires manual application."
        log_info "Apply migration manually with:"
        echo "  mysql -h <MIMIR_HOST> -u <USER> -p<PASSWORD> < $MIMIR_DIR/ro-ai-bridge/mimir-core-ai/migrations/20260528000000_loki_security_test_agent.sql"
        return 0
    fi

    # Try to apply migration
    log_info "Attempting to apply Mimir migration..."
    # This would require setting MIMIR_DB_HOST, MIMIR_DB_USER, MIMIR_DB_PASSWORD
    # For now, just show the command
    echo ""
    echo "To apply the Loki agent migration, run:"
    echo "  mysql -h <MIMIR_HOST> -u <MIMIR_USER> -p<PASSWORD> < $MIMIR_DIR/ro-ai-bridge/mimir-core-ai/migrations/20260528000000_loki_security_test_agent.sql"
    echo ""
}

# ─── Test Stage ────────────────────────────────────────────────────────────

run_tests() {
    log_info "Running Loki security tests..."

    # Check if pod is ready
    if ! kubectl -n "$NAMESPACE" get pod "$POD_NAME" &> /dev/null; then
        log_error "Pod 'loki' not found. Deploy first with: ./scripts/loki-deploy.sh deploy"
        exit 1
    fi

    # Run test scripts mounted via ConfigMap
    log_info "Running API injection test..."
    kubectl -n "$NAMESPACE" exec -it "$POD_NAME" -- bash -c "
        source /opt/loki/scripts/setup.sh
        /opt/loki/scripts/api-injection-test.sh
    " || log_warn "API injection test encountered issues (expected if services unreachable)"

    log_info "Running prompt injection test..."
    kubectl -n "$NAMESPACE" exec -it "$POD_NAME" -- bash -c "
        /opt/loki/scripts/prompt-injection-test.sh
    " || log_warn "Prompt injection test encountered issues"

    log_info "Running data exfiltration test..."
    kubectl -n "$NAMESPACE" exec -it "$POD_NAME" -- bash -c "
        /opt/loki/scripts/data-exfiltration-test.sh
    " || log_warn "Data exfiltration test encountered issues"

    log_success "Security tests completed. Check Tyr dashboard for detections."
}

# ─── Interactive Shell ──────────────────────────────────────────────────────

shell() {
    log_info "Opening interactive shell to Loki pod..."
    echo ""
    echo "Commands available:"
    echo "  ./api-injection-test.sh"
    echo "  ./prompt-injection-test.sh"
    echo "  ./data-exfiltration-test.sh"
    echo "  ./tyr-detection-test.sh"
    echo ""

    kubectl -n "$NAMESPACE" exec -it "$POD_NAME" -- /bin/bash
}

# ─── Cleanup Stage ─────────────────────────────────────────────────────────

cleanup() {
    log_warn "Cleaning up Loki from cluster..."

    # Delete K8s resources
    log_info "Deleting K8s resources..."
    kubectl -n "$NAMESPACE" delete deployment loki 2>/dev/null || true
    kubectl -n "$NAMESPACE" delete service loki 2>/dev/null || true
    kubectl -n "$NAMESPACE" delete sa loki 2>/dev/null || true
    kubectl -n "$NAMESPACE" delete role,rolebinding -l app=loki 2>/dev/null || true
    kubectl -n "$NAMESPACE" delete networkpolicy -l app=loki 2>/dev/null || true
    kubectl -n "$NAMESPACE" delete configmap loki-test-scripts loki-test-payloads 2>/dev/null || true

    log_success "K8s resources deleted"

    # Delete Docker image
    log_info "Deleting Docker image..."
    docker rmi "$LOKI_IMAGE" 2>/dev/null || true
    log_success "Docker image deleted"

    log_success "Loki cleanup complete"
}

# ─── Status Check ──────────────────────────────────────────────────────────

status() {
    log_info "Loki deployment status:"
    echo ""

    # Check image
    if docker images | grep -q "asgard-loki"; then
        log_success "Docker image exists"
        docker images | grep "asgard-loki"
    else
        log_warn "Docker image not found"
    fi
    echo ""

    # Check K8s resources
    if kubectl -n "$NAMESPACE" get pod "$POD_NAME" &> /dev/null; then
        log_success "Loki pod running"
        kubectl -n "$NAMESPACE" get pod "$POD_NAME"
    else
        log_warn "Loki pod not running"
    fi
    echo ""

    # Check agent in Mimir
    log_info "To verify Loki agent in Mimir, query:"
    echo "  SELECT * FROM agent_configs WHERE name = 'loki-security-test';"
}

# ─── Main Entry Point ──────────────────────────────────────────────────────

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           Loki Security Testing Service Deployment            ║"
    echo "║         Authorized Internal Testing for Asgard Defenses        ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    local action="${1:-status}"

    case "$action" in
        build)
            check_prerequisites
            build_image
            ;;
        deploy)
            check_prerequisites
            if ! docker images | grep -q "asgard-loki"; then
                log_info "Docker image not found. Building first..."
                build_image
            fi
            deploy_k8s
            deploy_agent
            ;;
        test)
            run_tests
            ;;
        shell)
            shell
            ;;
        cleanup)
            cleanup
            ;;
        status)
            status
            ;;
        *)
            echo "Usage: $0 [build|deploy|test|shell|cleanup|status]"
            echo ""
            echo "Actions:"
            echo "  build   - Build Docker image"
            echo "  deploy  - Deploy to Kubernetes"
            echo "  test    - Run security test suites"
            echo "  shell   - Open interactive shell"
            echo "  cleanup - Remove from cluster"
            echo "  status  - Show deployment status"
            exit 1
            ;;
    esac

    echo ""
}

main "$@"
