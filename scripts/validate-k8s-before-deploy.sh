#!/bin/bash
# Validate K8s manifests before deployment
# Prevents configuration errors like INC-2026-05-17-001

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/../k8s"

echo -e "${GREEN}🔍 Validating K8s manifests...${NC}\n"

ERRORS=0
WARNINGS=0

# ============================================
# Check 1: MariaDB Secret has all required vars
# ============================================

echo "Checking MariaDB secret (k8s/01-infra/mariadb/deployment.yaml)..."

MARIADB_MANIFEST="$K8S_DIR/01-infra/mariadb/deployment.yaml"

if [ ! -f "$MARIADB_MANIFEST" ]; then
  echo -e "  ${RED}✗${NC} MariaDB manifest not found: $MARIADB_MANIFEST"
  ERRORS=$((ERRORS + 1))
else
  REQUIRED_MARIADB_VARS=(
    "MYSQL_ROOT_PASSWORD"
    "MYSQL_DATABASE"
    "MYSQL_USER"
    "MYSQL_PASSWORD"
  )

  for var in "${REQUIRED_MARIADB_VARS[@]}"; do
    if grep -q "^  $var:" "$MARIADB_MANIFEST"; then
      echo -e "  ${GREEN}✓${NC} $var found"
    else
      echo -e "  ${RED}✗${NC} $var MISSING in $MARIADB_MANIFEST"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check for placeholder passwords
  if grep -q "REDACTED-PW" "$MARIADB_MANIFEST"; then
    echo -e "  ${RED}✗${NC} REDACTED-PW placeholder found — replace with actual password"
    ERRORS=$((ERRORS + 1))
  else
    echo -e "  ${GREEN}✓${NC} No placeholder passwords"
  fi
fi

# ============================================
# Check 2: Password Parity — Secret matches DATABASE_URL
# ============================================

echo -e "\nChecking password parity (Secret vs DATABASE_URL)..."

DB_URL=$(kubectl get secret -n asgard asgard-secrets \
  -o jsonpath='{.data.MIMIR_DATABASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)

if [ -z "$DB_URL" ]; then
  echo -e "  ${YELLOW}⚠${NC}  Could not read MIMIR_DATABASE_URL from asgard-secrets (cluster may be offline)"
  WARNINGS=$((WARNINGS + 1))
else
  # Extract password from DATABASE_URL
  DB_PASS=$(echo "$DB_URL" | sed -E 's|mysql://[^:]+:([^@]+)@.*|\1|')
  MANIFEST_PASS=$(grep "MYSQL_PASSWORD:" "$MARIADB_MANIFEST" | awk '{print $2}' | tr -d '"' | tail -1)

  if [ "$DB_PASS" = "$MANIFEST_PASS" ]; then
    echo -e "  ${GREEN}✓${NC} Passwords match (Secret == DATABASE_URL)"
  else
    echo -e "  ${RED}✗${NC} Password MISMATCH — Secret password ≠ DATABASE_URL password"
    echo -e "       This will cause ERROR 1045 Access denied"
    ERRORS=$((ERRORS + 1))
  fi
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
  pvc="${pvc_spec%%:*}"
  ns="${pvc_spec##*:}"

  if kubectl get pvc "$pvc" -n "$ns" &>/dev/null; then
    STATUS=$(kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}')
    if [ "$STATUS" = "Bound" ]; then
      echo -e "  ${GREEN}✓${NC} PVC $pvc in $ns (Bound)"
    else
      echo -e "  ${YELLOW}⚠${NC}  PVC $pvc in $ns is $STATUS (not Bound)"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "  ${YELLOW}⚠${NC}  PVC $pvc not found in $ns (will be created on deploy)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ============================================
# Check 4: Required Secrets Exist in Cluster
# ============================================

echo -e "\nChecking required secrets in cluster..."

REQUIRED_SECRETS=(
  "asgard-secrets:asgard"
  "mariadb-secret:asgard-infra"
)

for secret_spec in "${REQUIRED_SECRETS[@]}"; do
  secret="${secret_spec%%:*}"
  ns="${secret_spec##*:}"

  if kubectl get secret "$secret" -n "$ns" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Secret $secret exists in $ns"
  else
    echo -e "  ${RED}✗${NC} Secret $secret not found in $ns"
    ERRORS=$((ERRORS + 1))
  fi
done

# ============================================
# Check 5: No Placeholder Values in Manifests
# ============================================

echo -e "\nChecking for placeholder values..."

PLACEHOLDER_FOUND=false
while IFS= read -r -d '' file; do
  if grep -q "REDACTED-PW\|CHANGE_ME\|YOUR_PASSWORD\|<password>" "$file" 2>/dev/null; then
    echo -e "  ${RED}✗${NC} Placeholder found in: $file"
    PLACEHOLDER_FOUND=true
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$K8S_DIR" -name "*.yaml" -print0)

if [ "$PLACEHOLDER_FOUND" = false ]; then
  echo -e "  ${GREEN}✓${NC} No placeholder values found"
fi

# ============================================
# Summary
# ============================================

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ Validation passed!${NC}"
  if [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}⚠  $WARNINGS warnings (non-blocking, see above)${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "\n${GREEN}Safe to deploy:${NC}"
  echo "  ./scripts/deploy-all.sh"
  exit 0
else
  echo -e "${RED}❌ Validation FAILED — $ERRORS critical error(s)${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "\n${RED}Fix all errors above before deploying${NC}"
  exit 1
fi
