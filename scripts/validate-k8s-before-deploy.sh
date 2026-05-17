#!/bin/bash
# Validate K8s manifests before deployment
# Prevents:
#   - INC-2026-05-17-001 class: missing credentials → MariaDB auto-init fails
#   - INC-2026-05-17 follow-up class: plaintext credentials committed to git
#
# Policy reference: docs/security/SECRETS.md
#   "no plaintext rendering in deployment manifests"

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
# Check 1: No plaintext credentials in manifests
# ============================================
# Policy: docs/security/SECRETS.md — credential fields MUST use
# valueFrom:secretKeyRef or envFrom:secretRef. Never `value:` literal.

echo "Check 1: Plaintext credentials in env: blocks..."

# Uses awk for precision: pairs each `name:` with its following `value:` and
# only flags values that (a) belong to a credential-shaped name and
# (b) are not safe protocols (sqlite:, http:, file:).
PLAINTEXT_HITS=""
while IFS= read -r -d '' file; do
  hits=$(awk '
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*[A-Z_][A-Z0-9_]*[[:space:]]*$/ {
      n = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", n)
      sub(/[[:space:]]*$/, "", n)
      name = n
      lineno = NR
      next
    }
    /^[[:space:]]*value:[[:space:]]*[^[:space:]]/ {
      if (name == "") next
      is_cred = 0
      if (name ~ /(PASSWORD|MASTERKEY|MASTER_KEY)$/) is_cred = 1
      if (name ~ /_SECRET$/ || name == "SECRET") is_cred = 1
      if (name ~ /_TOKEN$/ || name == "TOKEN" || name == "VAULT_TOKEN") is_cred = 1
      if (name ~ /API_KEY$/) is_cred = 1
      if (name == "DATABASE_URL" || name == "NEO4J_AUTH") is_cred = 1
      if (name == "MINIO_ROOT_USER" || name == "MINIO_ROOT_PASSWORD") is_cred = 1
      if (is_cred) {
        val = $0
        sub(/^[[:space:]]*value:[[:space:]]*"?/, "", val)
        sub(/"?[[:space:]]*$/, "", val)
        # Skip safe placeholders / non-credential URL schemes
        if (val !~ /^(sqlite:|file:|http:\/\/|https:\/\/|<.*>$)/) {
          print FILENAME ":" lineno ": " name " = " val
        }
      }
      name = ""
    }
  ' "$file")
  if [ -n "$hits" ]; then
    PLAINTEXT_HITS="$PLAINTEXT_HITS"$'\n'"$hits"
  fi
done < <(find "$K8S_DIR" -name "*.yaml" -print0)

PLAINTEXT_HITS=$(echo "$PLAINTEXT_HITS" | sed '/^$/d')

if [ -z "$PLAINTEXT_HITS" ]; then
  echo -e "  ${GREEN}✓${NC} No plaintext credentials in env: blocks"
else
  echo -e "  ${RED}✗${NC} Plaintext credentials found — must use secretKeyRef/envFrom:"
  echo "$PLAINTEXT_HITS" | head -20 | sed 's/^/      /'
  ERRORS=$((ERRORS + 1))
fi

# ============================================
# Check 2: No Secret resources with stringData in git
# ============================================
# Policy: docs/security/SECRETS.md — Secrets must be created out-of-band.
# Manifests may keep commented-out Secret blocks as schema documentation only.

echo -e "\nCheck 2: Live Secret resources committed to git..."

LIVE_SECRETS=$(grep -rEn "^kind:\s*Secret\s*$" "$K8S_DIR" --include="*.yaml" 2>/dev/null | grep -vE "^\s*#" || true)

if [ -z "$LIVE_SECRETS" ]; then
  echo -e "  ${GREEN}✓${NC} No live Secret resources in manifests (commented-out schema is fine)"
else
  echo -e "  ${RED}✗${NC} Live Secret resources found — comment them out and create via kubectl:"
  echo "$LIVE_SECRETS" | sed 's/^/      /'
  ERRORS=$((ERRORS + 1))
fi

# ============================================
# Check 3: Placeholder values
# ============================================

echo -e "\nCheck 3: Placeholder values (REDACTED-PW, CHANGE_ME, etc)..."

PLACEHOLDER_HITS=$(grep -rEn "REDACTED-PW|CHANGE_ME|YOUR_PASSWORD|<password>|TODO_FILL" "$K8S_DIR" --include="*.yaml" 2>/dev/null \
  | grep -vE "^\s*#|<REDACTED — see " || true)

if [ -z "$PLACEHOLDER_HITS" ]; then
  echo -e "  ${GREEN}✓${NC} No active placeholder values found"
else
  echo -e "  ${RED}✗${NC} Placeholder values found (uncommented):"
  echo "$PLACEHOLDER_HITS" | head -10 | sed 's/^/      /'
  ERRORS=$((ERRORS + 1))
fi

# ============================================
# Check 4: Required cluster Secrets exist
# ============================================

echo -e "\nCheck 4: Required cluster Secrets exist..."

REQUIRED_SECRETS=(
  "asgard-secrets:asgard"
  "mariadb-secret:asgard-infra"
  "neo4j-secret:asgard-infra"
  "postgres-secret:asgard-infra"
)

for secret_spec in "${REQUIRED_SECRETS[@]}"; do
  secret="${secret_spec%%:*}"
  ns="${secret_spec##*:}"

  if kubectl get secret "$secret" -n "$ns" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $secret in $ns"
  else
    echo -e "  ${RED}✗${NC} $secret missing in $ns — see deployment.yaml comment for create command"
    ERRORS=$((ERRORS + 1))
  fi
done

# ============================================
# Check 5: Secret/asgard-secrets value consistency
# ============================================
# Detects the INC-2026-05-17 follow-up class: mariadb-secret diverged from
# asgard-secrets:MARIADB_PASSWORD. On PVC delete, MariaDB auto-init uses
# mariadb-secret, but Mimir connects via asgard-secrets:MIMIR_DATABASE_URL.
# Mismatch → ERROR 1045 outage.

echo -e "\nCheck 5: mariadb-secret consistency with asgard-secrets..."

if ! kubectl get secret asgard-secrets -n asgard &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  Cluster offline or asgard-secrets missing — skipping"
  WARNINGS=$((WARNINGS + 1))
elif ! kubectl get secret mariadb-secret -n asgard-infra &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  mariadb-secret missing — skipping (Check 4 will catch it)"
  WARNINGS=$((WARNINGS + 1))
else
  ASGARD_PW=$(kubectl get secret asgard-secrets -n asgard -o jsonpath='{.data.MARIADB_PASSWORD}' | base64 -d 2>/dev/null)
  MARIADB_PW=$(kubectl get secret mariadb-secret -n asgard-infra -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d 2>/dev/null)

  if [ -z "$ASGARD_PW" ] || [ -z "$MARIADB_PW" ]; then
    echo -e "  ${YELLOW}⚠${NC}  Could not read one of the secret values"
    WARNINGS=$((WARNINGS + 1))
  elif [ "$ASGARD_PW" = "$MARIADB_PW" ]; then
    echo -e "  ${GREEN}✓${NC} mariadb-secret.MYSQL_PASSWORD == asgard-secrets.MARIADB_PASSWORD"
  else
    echo -e "  ${RED}✗${NC} DIVERGENCE — mariadb-secret ≠ asgard-secrets.MARIADB_PASSWORD"
    echo -e "       PVC deletion + auto-init will use the WRONG password and recreate INC-2026-05-17-001"
    echo -e "       Run: ./scripts/reconcile-mariadb-secret.sh"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ============================================
# Check 6: PersistentVolumeClaims status
# ============================================

echo -e "\nCheck 6: PersistentVolumeClaims..."

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
      echo -e "  ${GREEN}✓${NC} $pvc in $ns (Bound)"
    else
      echo -e "  ${YELLOW}⚠${NC}  $pvc in $ns is $STATUS"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "  ${YELLOW}⚠${NC}  $pvc not found in $ns (will be created on deploy)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ============================================
# Summary
# ============================================

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ Validation passed!${NC}"
  if [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}⚠  $WARNINGS warnings (non-blocking)${NC}"
  fi
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  exit 0
else
  echo -e "${RED}❌ Validation FAILED — $ERRORS critical error(s)${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "\n${RED}Fix all errors above before deploying.${NC}"
  echo -e "Reference: docs/security/SECRETS.md"
  exit 1
fi
