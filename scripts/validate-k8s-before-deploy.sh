#!/bin/bash
# Validate K8s manifests before deployment
# Prevents configuration errors like INC-2026-05-17-001

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Validating K8s manifests...${NC}\n"

ERRORS=0
WARNINGS=0

# ============================================
# Check 1: MariaDB Required Environment Variables
# ============================================

echo "Checking MariaDB deployment..."

REQUIRED_MARIADB_VARS=(
  "MYSQL_ROOT_PASSWORD"
  "MYSQL_DATABASE"
  "MYSQL_USER"
  "MYSQL_PASSWORD"
)

for var in "${REQUIRED_MARIADB_VARS[@]}"; do
  if kubectl kustomize k8s/asgard-infra 2>/dev/null | grep -q "name: $var"; then
    echo -e "  ${GREEN}✓${NC} $var found"
  else
    echo -e "  ${RED}✗${NC} $var MISSING in MariaDB deployment"
    ERRORS=$((ERRORS + 1))
  fi
done

# ============================================
# Check 2: Image Pull Policy for K3s
# ============================================

echo -e "\nChecking image pull policies..."

# K3s uses local Docker images, should use imagePullPolicy: Never
if kubectl kustomize k8s/asgard 2>/dev/null | grep -q "imagePullPolicy: Never"; then
  echo -e "  ${GREEN}✓${NC} imagePullPolicy: Never (correct for K3s)"
else
  echo -e "  ${YELLOW}⚠${NC}  Some images may use imagePullPolicy: IfNotPresent (may cause delays)"
  WARNINGS=$((WARNINGS + 1))
fi

# ============================================
# Check 3: PersistentVolumeClaims Exist
# ============================================

echo -e "\nChecking PersistentVolumeClaims..."

REQUIRED_PVCS=(
  "mariadb-data:asgard-infra"
  "postgres-data:asgard-infra"
  "qdrant-data:asgard-infra"
)

for pvc_spec in "${REQUIRED_PVCS[@]}"; do
  pvc=$(echo $pvc_spec | cut -d: -f1)
  ns=$(echo $pvc_spec | cut -d: -f2)

  if kubectl get pvc $pvc -n $ns &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} PVC $pvc exists in $ns"
  else
    echo -e "  ${YELLOW}⚠${NC}  PVC $pvc not found in $ns (will be created on deploy)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ============================================
# Check 4: Secrets Configured
# ============================================

echo -e "\nChecking required secrets..."

REQUIRED_SECRETS=(
  "asgard-secrets:asgard"
  "mariadb-secrets:asgard-infra"
)

for secret_spec in "${REQUIRED_SECRETS[@]}"; do
  secret=$(echo $secret_spec | cut -d: -f1)
  ns=$(echo $secret_spec | cut -d: -f2)

  if kubectl get secret $secret -n $ns &>/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Secret $secret exists in $ns"
  else
    echo -e "  ${YELLOW}⚠${NC}  Secret $secret not found in $ns"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ============================================
# Check 5: Health Check Configuration
# ============================================

echo -e "\nChecking health checks..."

if kubectl kustomize k8s/asgard 2>/dev/null | grep -q "readinessProbe\|livenessProbe"; then
  echo -e "  ${GREEN}✓${NC} Health checks configured"
else
  echo -e "  ${YELLOW}⚠${NC}  Some deployments missing health checks"
  WARNINGS=$((WARNINGS + 1))
fi

# ============================================
# Summary
# ============================================

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✅ Validation passed!${NC}"
  if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠  $WARNINGS warnings found (see above)${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "\n${GREEN}Safe to deploy:${NC}"
  echo "  kubectl apply -f k8s/"
  exit 0
else
  echo -e "${RED}❌ Validation failed! Found $ERRORS critical errors${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "\n${RED}Fix the errors above before deploying${NC}"
  exit 1
fi
