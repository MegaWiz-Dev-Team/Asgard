#!/bin/bash
# Force-reset Neo4j password (INC-2026-05-17-001 P0 followup, O1b + O5)
#
# Current Neo4j password is unknown (NEO4J_AUTH was edited post-first-boot
# and silently ignored). This script does a force-reset by clearing the
# auth files in /data/dbms while Neo4j is stopped, then bringing it back
# up — Neo4j will then honor NEO4J_AUTH from neo4j-secret as if first boot.
#
# Graph data is NOT touched. Only the auth state is reset.
#
# Steps:
#   1. Update asgard-secrets.NEO4J_PASSWORD
#   2. Create/refresh neo4j-secret via reconcile script
#   3. Scale Neo4j down to 0
#   4. Clear /data/dbms/auth* via helper pod
#   5. Apply new neo4j/deployment.yaml (uses secretKeyRef)
#   6. Scale Neo4j back to 1 — first-boot logic creates user with new password
#   7. Verify cypher auth
#   8. Restart Bifrost (picks up new NEO4J_PASSWORD via envFrom)

set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}Neo4j password force-reset${NC}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${YELLOW}This is a force-reset, not a rotation:${NC}"
echo "  the current Neo4j password is unknown (set on first boot, never recorded)."
echo "  Auth files in /data/dbms will be cleared. Graph data is preserved."
echo ""

# ----- Prompt for new password (twice) -----
IFS= read -rsp "Enter NEW Neo4j password (hidden): " NEW_PW
echo
IFS= read -rsp "Confirm NEW Neo4j password:        " NEW_PW_CONFIRM
echo
echo

if [ -z "$NEW_PW" ]; then
  echo "${RED}❌ Password empty — abort${NC}"; exit 1
fi
if [ "$NEW_PW" != "$NEW_PW_CONFIRM" ]; then
  echo "${RED}❌ Passwords don't match — abort${NC}"; exit 1
fi
if [ ${#NEW_PW} -lt 16 ]; then
  echo "${YELLOW}⚠  Password is shorter than 16 chars.${NC}"
  read -rp "Continue anyway? (y/N) " yn
  [ "$yn" = "y" ] || exit 1
fi
# Neo4j has password complexity requirements; minimum 8 chars
if [ ${#NEW_PW} -lt 8 ]; then
  echo "${RED}❌ Neo4j requires password ≥ 8 chars${NC}"; exit 1
fi

# Backup current asgard-secrets NEO4J_PASSWORD for the record
CURRENT_PW=$(kubectl get secret asgard-secrets -n asgard \
  -o jsonpath='{.data.NEO4J_PASSWORD}' 2>/dev/null | base64 -d || true)
BACKUP_FILE="/tmp/asgard-neo4j-rollback-$(date +%Y%m%d-%H%M%S).txt"
umask 077
{
  echo "# Neo4j rotation record — $(date -Iseconds)"
  echo "# Previous asgard-secrets.NEO4J_PASSWORD (NOT necessarily the live password):"
  echo "OLD_NEO4J_PASSWORD_SECRET=$CURRENT_PW"
} > "$BACKUP_FILE"
echo "📋 Backup record at ${BACKUP_FILE}"

# ----- Final confirmation -----
echo ""
echo "About to:"
echo "  1. Patch asgard-secrets.NEO4J_PASSWORD = <new>"
echo "  2. Create/refresh neo4j-secret in asgard-infra"
echo "  3. Scale deployment/neo4j → 0 (Neo4j goes offline)"
echo "  4. Helper pod: rm -f /data/dbms/auth* /data/dbms/auth.ini"
echo "  5. Apply k8s/01-infra/neo4j/deployment.yaml"
echo "  6. Scale deployment/neo4j → 1"
echo "  7. Verify cypher with new password"
echo "  8. Roll restart deployment/bifrost"
echo ""
echo "Expected Neo4j downtime: ~2 minutes."
read -rp "Proceed? type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Cancelled. Backup record preserved at ${BACKUP_FILE}"; exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================
# Step 1: Patch asgard-secrets
# ============================================
echo ""
echo "🔄 Step 1/8: Patch asgard-secrets.NEO4J_PASSWORD…"
NEW_PW_B64=$(printf '%s' "$NEW_PW" | base64 | tr -d '\n')
kubectl patch secret asgard-secrets -n asgard --type=json -p="[
  {\"op\": \"replace\", \"path\": \"/data/NEO4J_PASSWORD\", \"value\": \"$NEW_PW_B64\"}
]"
echo "   ${GREEN}✓${NC} asgard-secrets updated"

# ============================================
# Step 2: Reconcile neo4j-secret
# ============================================
echo ""
echo "🔄 Step 2/8: Create/refresh neo4j-secret…"
"$SCRIPT_DIR/reconcile-neo4j-secret.sh" > /dev/null
echo "   ${GREEN}✓${NC} neo4j-secret in asgard-infra now holds NEO4J_AUTH=neo4j/<new>"

# ============================================
# Step 3: Scale Neo4j down
# ============================================
echo ""
echo "🔄 Step 3/8: Scale deployment/neo4j → 0…"
kubectl scale deployment/neo4j -n asgard-infra --replicas=0
kubectl wait --for=delete pod -l app=neo4j -n asgard-infra --timeout=90s
echo "   ${GREEN}✓${NC} Neo4j pod terminated"

# ============================================
# Step 4: Clear auth files via helper pod
# ============================================
echo ""
echo "🔄 Step 4/8: Clear auth state in /data/dbms…"

# Use kubectl run + --overrides for PVC mount
cat <<'EOF' > /tmp/neo4j-auth-reset.yaml
apiVersion: v1
kind: Pod
metadata:
  name: neo4j-auth-reset
  namespace: asgard-infra
spec:
  restartPolicy: Never
  containers:
    - name: reset
      image: busybox:1.36
      command: ["sh","-c"]
      args:
        - |
          echo "Before:"
          ls -la /data/dbms/ 2>/dev/null || echo "  (dbms not yet created)"
          rm -f /data/dbms/auth /data/dbms/auth.ini
          echo ""
          echo "After:"
          ls -la /data/dbms/ 2>/dev/null || echo "  (dbms not yet created)"
          echo ""
          echo "DONE"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: neo4j-data
EOF

kubectl delete pod neo4j-auth-reset -n asgard-infra --ignore-not-found --wait=true >/dev/null
kubectl apply -f /tmp/neo4j-auth-reset.yaml
kubectl wait --for=condition=Ready pod/neo4j-auth-reset -n asgard-infra --timeout=30s 2>/dev/null || true
# Wait for pod to finish (it's Never-restart so it'll go Succeeded)
for i in 1 2 3 4 5 6 7 8 9 10; do
  PHASE=$(kubectl get pod neo4j-auth-reset -n asgard-infra -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  [ "$PHASE" = "Succeeded" ] && break
  sleep 2
done
kubectl logs neo4j-auth-reset -n asgard-infra | sed 's/^/   /'
kubectl delete pod neo4j-auth-reset -n asgard-infra --wait=true >/dev/null
rm -f /tmp/neo4j-auth-reset.yaml
echo "   ${GREEN}✓${NC} Auth files cleared"

# ============================================
# Step 5: Apply new manifest
# ============================================
echo ""
echo "🔄 Step 5/8: Apply k8s/01-infra/neo4j/deployment.yaml…"
kubectl apply -f "$REPO_DIR/k8s/01-infra/neo4j/deployment.yaml"
echo "   ${GREEN}✓${NC} Manifest applied"

# ============================================
# Step 6: Scale Neo4j back up
# ============================================
echo ""
echo "🔄 Step 6/8: Scale deployment/neo4j → 1…"
kubectl scale deployment/neo4j -n asgard-infra --replicas=1
kubectl rollout status deployment/neo4j -n asgard-infra --timeout=180s
sleep 5  # give bolt port a moment to come up after Ready
echo "   ${GREEN}✓${NC} Neo4j pod ready"

# ============================================
# Step 7: Verify cypher auth
# ============================================
echo ""
echo "🔄 Step 7/8: Verify cypher with new password…"
ATTEMPTS=0
until kubectl exec -n asgard-infra deploy/neo4j -- bash -c \
        "echo 'RETURN 1 AS ok;' | cypher-shell -u neo4j -p '$NEW_PW'" >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -ge 12 ]; then
    echo "   ${RED}✗${NC} cypher auth failed after 12 attempts — investigate"
    echo "       kubectl logs deploy/neo4j -n asgard-infra"
    exit 1
  fi
  sleep 5
done
echo "   ${GREEN}✓${NC} cypher authenticates with new password"

# ============================================
# Step 8: Restart Bifrost
# ============================================
echo ""
echo "🔄 Step 8/8: Apply bifrost manifest + roll restart…"
kubectl apply -f "$REPO_DIR/k8s/02-services/bifrost/deployment.yaml"
kubectl rollout restart deployment/bifrost -n asgard
kubectl rollout status  deployment/bifrost -n asgard --timeout=90s
echo "   ${GREEN}✓${NC} Bifrost restarted"

# ============================================
# Final verification
# ============================================
echo ""
echo "🔍 Final verification…"
BIFROST_PW=$(kubectl exec -n asgard deploy/bifrost -- printenv NEO4J_PASSWORD 2>/dev/null || echo "")
if [ "$BIFROST_PW" = "$NEW_PW" ]; then
  echo "   ${GREEN}✓${NC} Bifrost env NEO4J_PASSWORD now matches new value"
else
  echo "   ${YELLOW}⚠${NC}  Bifrost env NEO4J_PASSWORD differs from new value (check secretKeyRef)"
fi

echo ""
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}✅ Neo4j force-reset complete${NC}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Record file (delete when no longer needed):  ${BACKUP_FILE}"
echo ""
echo "Run ./scripts/validate-k8s-before-deploy.sh to confirm all checks pass."
