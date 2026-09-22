#!/bin/bash
# Create / reconcile neo4j-secret from asgard-secrets:NEO4J_PASSWORD
#
# Required after the INC-2026-05-17 follow-up which moved NEO4J_AUTH out of
# the neo4j Deployment manifest into a Secret (per postgres pattern).

set -euo pipefail

NAMESPACE_INFRA=asgard-infra
NAMESPACE_APP=asgard

echo "🔍 Reading NEO4J_PASSWORD from asgard-secrets…"

NEO4J_PW=$(kubectl get secret asgard-secrets -n "$NAMESPACE_APP" -o jsonpath='{.data.NEO4J_PASSWORD}' | base64 -d)

if [ -z "$NEO4J_PW" ]; then
  echo "❌ asgard-secrets does not contain NEO4J_PASSWORD"
  exit 1
fi

echo "🔄 Creating neo4j-secret in $NAMESPACE_INFRA with NEO4J_AUTH = neo4j/<password>…"

kubectl create secret generic neo4j-secret -n "$NAMESPACE_INFRA" \
  --from-literal=NEO4J_AUTH="neo4j/${NEO4J_PW}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Reconcile complete."
echo ""
echo "⚠️  Note: NEO4J_AUTH is only honored by Neo4j on FIRST boot of a fresh data volume."
echo "    If Neo4j already has data, the existing user password is unchanged."
echo "    To rotate: kubectl exec deploy/neo4j -n $NAMESPACE_INFRA -- cypher-shell -u neo4j -p <old-pw>"
echo "               \"ALTER USER neo4j SET PASSWORD '<new-pw>';\""
