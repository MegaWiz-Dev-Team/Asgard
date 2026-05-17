#!/bin/bash
# Reconcile mariadb-secret to match asgard-secrets:MARIADB_PASSWORD
#
# Background: INC-2026-05-17-001 follow-up review found that the cluster's
# mariadb-secret had drifted from asgard-secrets:MARIADB_PASSWORD. Because
# MariaDB auto-init on a fresh PVC reads mariadb-secret, this drift would
# recreate the outage on next PVC deletion.
#
# This script makes mariadb-secret consistent with asgard-secrets, which is
# the documented source of truth per docs/security/SECRETS.md.

set -euo pipefail

NAMESPACE_INFRA=asgard-infra
NAMESPACE_APP=asgard

echo "🔍 Reading source-of-truth values from asgard-secrets…"

ROOT_PW=$(kubectl get secret asgard-secrets -n "$NAMESPACE_APP" -o jsonpath='{.data.MARIADB_ROOT_PASSWORD}' | base64 -d)
APP_PW=$(kubectl  get secret asgard-secrets -n "$NAMESPACE_APP" -o jsonpath='{.data.MARIADB_PASSWORD}'      | base64 -d)

if [ -z "$ROOT_PW" ] || [ -z "$APP_PW" ]; then
  echo "❌ asgard-secrets does not contain MARIADB_ROOT_PASSWORD or MARIADB_PASSWORD"
  exit 1
fi

echo "🔄 Recreating mariadb-secret in ${NAMESPACE_INFRA}..."

kubectl create secret generic mariadb-secret -n "$NAMESPACE_INFRA" \
  --from-literal=MYSQL_ROOT_PASSWORD="$ROOT_PW" \
  --from-literal=MYSQL_DATABASE=mimir \
  --from-literal=MYSQL_USER=mimir \
  --from-literal=MYSQL_PASSWORD="$APP_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "🔄 Aligning live MariaDB user password (in case auto-init used the old value)…"

# Find pod
POD=$(kubectl get pod -n "$NAMESPACE_INFRA" -l app=mariadb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$POD" ]; then
  echo "⚠️  MariaDB pod not found — skipping ALTER USER (will apply on next pod start)"
else
  kubectl exec -n "$NAMESPACE_INFRA" "$POD" -- \
    mariadb -u root -p"$ROOT_PW" -e \
    "ALTER USER 'mimir'@'%' IDENTIFIED BY '$APP_PW'; FLUSH PRIVILEGES;" \
    && echo "✅ Live MariaDB password aligned"
fi

echo ""
echo "✅ Reconcile complete."
echo "   Verify: ./scripts/validate-k8s-before-deploy.sh (Check 5 should pass)"
