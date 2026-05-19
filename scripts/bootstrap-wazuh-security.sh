#!/usr/bin/env bash
# Manual recovery for Wazuh OpenSearch security index.
#
# Background: on 2026-05-17 OrbStack restart corrupted the
# `.opendistro_security` index on the wazuh-indexer PVC. The indexer
# rejected every query with `503 Service Unavailable: OpenSearch Security
# not initialized`, breaking manager → indexer ingest and dashboard auth
# for ~2 days before manual recovery.
#
# Going forward [02-wazuh-indexer.yaml](../k8s/04-security/tyr/02-wazuh-indexer.yaml)
# auto-runs securityadmin.sh in a postStart hook on every pod start.
# This script is the operator fallback when the hook itself fails or when
# you want to force a re-bootstrap without restarting the pod.
#
# Idempotent: securityadmin.sh is itself idempotent (creates index if
# missing, updates configs in place otherwise).
#
# Usage:
#   ./scripts/bootstrap-wazuh-security.sh                # auto-recover
#   ./scripts/bootstrap-wazuh-security.sh --check        # status only, no write
#   ./scripts/bootstrap-wazuh-security.sh --restart-clients  # also restart manager+dashboard

set -euo pipefail

NS="${NS:-wazuh}"
INDEXER_POD="${INDEXER_POD:-wazuh-indexer-0}"
MODE="bootstrap"

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --restart-clients) MODE="restart-clients" ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 64
      ;;
  esac
done

log()  { printf '[bootstrap-wazuh] %s\n' "$*"; }
fail() { printf '[bootstrap-wazuh] ERROR: %s\n' "$*" >&2; exit 1; }

kubectl get pod -n "$NS" "$INDEXER_POD" >/dev/null 2>&1 \
  || fail "pod $NS/$INDEXER_POD not found — is the cluster reachable?"

log "checking cluster + security index state…"
status="$(
  kubectl exec -n "$NS" "$INDEXER_POD" -- bash -c '
    curl -sku admin:admin https://localhost:9200/_cluster/health 2>/dev/null \
      | grep -oE "\"status\":\"[a-z]+\"" \
      || curl -sk --cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
           https://localhost:9200/_cluster/health 2>/dev/null \
         | grep -oE "\"status\":\"[a-z]+\"" \
      || echo "\"status\":\"unreachable\""
  '
)"
log "cluster: $status"

has_security="$(
  kubectl exec -n "$NS" "$INDEXER_POD" -- bash -c '
    curl -sku admin:admin https://localhost:9200/_cat/indices/.opendistro_security 2>/dev/null \
      | grep -c ".opendistro_security" || true
  '
)"
if [ "$has_security" -gt 0 ]; then
  log "security index PRESENT"
else
  log "security index MISSING"
fi

if [ "$MODE" = "check" ]; then
  exit 0
fi

if [ "$has_security" -eq 0 ] || [ "$MODE" = "bootstrap" ]; then
  log "running securityadmin.sh inside $INDEXER_POD…"
  kubectl exec -n "$NS" "$INDEXER_POD" -- bash -c '
    export JAVA_HOME=/usr/share/wazuh-indexer/jdk
    CERTS=/usr/share/wazuh-indexer/certs
    SECDIR=/usr/share/wazuh-indexer/opensearch-security
    TOOL=/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh
    if [ ! -f "$CERTS/admin.pem" ]; then
      echo "admin.pem missing — fallback to indexer cert (pre-admin-cert deploy)"
      "$TOOL" -cd "$SECDIR" -icl -nhnv \
        -cacert "$CERTS/root-ca.pem" \
        -cert "$CERTS/indexer.pem" \
        -key "$CERTS/indexer-key.pem" \
        -h 127.0.0.1 -p 9200
    else
      "$TOOL" -cd "$SECDIR" -icl -nhnv \
        -cacert "$CERTS/root-ca.pem" \
        -cert "$CERTS/admin.pem" \
        -key "$CERTS/admin-key.pem" \
        -h 127.0.0.1 -p 9200
    fi
  ' | tail -25
  log "securityadmin complete"
fi

if [ "$MODE" = "restart-clients" ]; then
  log "restarting wazuh-manager and wazuh-dashboard…"
  kubectl rollout restart -n "$NS" statefulset/wazuh-manager deployment/wazuh-dashboard
  kubectl rollout status -n "$NS" statefulset/wazuh-manager --timeout=180s
  kubectl rollout status -n "$NS" deployment/wazuh-dashboard --timeout=180s
fi

log "post-recovery indices:"
kubectl exec -n "$NS" "$INDEXER_POD" -- \
  curl -sku admin:admin 'https://localhost:9200/_cat/indices?v' | head -20
