#!/usr/bin/env bash
# Behaviour tests for the pod lookup in scripts/backup-full-k8s.sh (pod_for, missing_pod)
# against a fake kubectl. Nothing here touches a real cluster.
#
#   bash tests/backup_pod_discovery_test.sh
#
# 2026-10-23: the backup passed ReplicaSet-hash pod prefixes ("mariadb-585"). After a
# rollout the asgard-infra MariaDB pod became mariadb-5c7…, the prefix stopped matching,
# and the `mimir` database was reported as SKIP ("no running pod") instead of being dumped.
set -uo pipefail

# Fail closed: a real kubectl reached by mistake has no cluster to talk to.
DEAD_KUBECONFIG="$(mktemp)"
cat > "$DEAD_KUBECONFIG" <<'EOF'
apiVersion: v1
kind: Config
clusters: [{name: dead, cluster: {server: "https://127.0.0.1:1"}}]
contexts: [{name: dead, context: {cluster: dead, user: dead}}]
users: [{name: dead, user: {token: dead}}]
current-context: dead
EOF
export KUBECONFIG="$DEAD_KUBECONFIG"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/backup-full-k8s.sh"
trap 'rm -f "$DEAD_KUBECONFIG"' EXIT
PASS=0; FAILED=0

# Load only the two functions under test (sourcing the script would run a backup).
FUNCS="$(sed -n '/^pod_for() {/,/^}/p; /^missing_pod() {/,/^}/p' "$SCRIPT")"
if [ -z "$FUNCS" ] || ! grep -q '^missing_pod() {' <<<"$FUNCS"; then
    echo "FAIL: pod_for / missing_pod not found in $SCRIPT"; exit 1
fi
eval "$FUNCS"

# Log/record stubs: collect what the script would report.
REPORT=""
LOG()    { :; }
OK()     { REPORT+="OK:$*|"; }
ERR()    { REPORT+="ERR:$*|"; }
SKIP()   { REPORT+="SKIP:$*|"; }
record() { REPORT+="REC:$1:$2|"; }

# Fake cluster:
#   asgard-infra/deploy mariadb  selector app=mariadb, replicas 1, running pod mariadb-5c77d79d9b-5mb8l
#   asgard-infra/deploy postgres selector app=postgres, replicas 1, NO running pod
#   asgard/deploy askr           selector app=askr, replicas 0
#   asgard/statefulset fafnir-vault selector app=fafnir-vault, running pod fafnir-vault-0
#   asgard pod laminar-clickhouse-abc (no workload object; prefix fallback)
kubectl() {
    local a="$*"
    case "$a" in
        "get deployment mariadb -n asgard-infra -o go-template="*) echo -n "app=mariadb," ;;
        "get deployment postgres -n asgard-infra -o go-template="*) echo -n "app=postgres," ;;
        "get deployment askr -n asgard -o go-template="*) echo -n "app=askr," ;;
        "get statefulset fafnir-vault -n asgard -o go-template="*) echo -n "app=fafnir-vault," ;;
        "get pods -n asgard-infra -l app=mariadb --field-selector=status.phase=Running -o jsonpath="*) echo -n "mariadb-5c77d79d9b-5mb8l" ;;
        "get pods -n asgard -l app=fafnir-vault --field-selector=status.phase=Running -o jsonpath="*) echo -n "fafnir-vault-0" ;;
        "get pods -n asgard-infra -l app=postgres --field-selector=status.phase=Running -o jsonpath="*) echo -n "" ;;
        "get pods -n asgard -l app=askr --field-selector=status.phase=Running -o jsonpath="*) echo -n "" ;;
        "get deployment postgres -n asgard-infra -o jsonpath={.spec.replicas}") echo -n "1" ;;
        "get deployment askr -n asgard -o jsonpath={.spec.replicas}") echo -n "0" ;;
        "get pods -n asgard --no-headers")
            printf '%s\n' "laminar-clickhouse-abc   1/1   Running   0   1d" "old-thing-xyz   0/1   Error   0   1d" ;;
        *) return 1 ;;
    esac
}

check() {  # $1=name $2=expected $3=actual
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAILED=$((FAILED + 1)); echo "FAIL: $1"; echo "  want: $2"; echo "  got:  $3"; fi
}

check "deployment name resolves to its running pod through the selector" \
    "mariadb-5c77d79d9b-5mb8l" "$(pod_for asgard-infra mariadb)"
check "statefulset name resolves through its selector" \
    "fafnir-vault-0" "$(pod_for asgard fafnir-vault)"
check "a name with no workload object falls back to the running-pod prefix" \
    "laminar-clickhouse-abc" "$(pod_for asgard laminar-clickhouse)"
check "a stale ReplicaSet-hash prefix no longer matches anything" \
    "" "$(pod_for asgard-infra mariadb-585)"

REPORT=""; missing_pod asgard-infra postgres Postgres postgres-asgard-infra-postgres
check "a workload that wants replicas but has no running pod is a FAIL" \
    "ERR:Postgres asgard-infra/postgres — 1 replica(s) wanted but no running pod|REC:postgres-asgard-infra-postgres:FAIL|" "$REPORT"

REPORT=""; missing_pod asgard askr Askr askr
check "a workload scaled to 0 is a SKIP" \
    "SKIP:Askr asgard/askr — no running pod|REC:askr:SKIP|" "$REPORT"

REPORT=""; missing_pod asgard laminar-postgres Postgres postgres-asgard-laminar-postgres
check "a workload that does not exist is a SKIP" \
    "SKIP:Postgres asgard/laminar-postgres — no running pod|REC:postgres-asgard-laminar-postgres:SKIP|" "$REPORT"

for prefix in mariadb-67c mariadb-585 postgres-64 postgres-66 qdrant-cf qdrant-5f; do
    if grep -qE "^backup_(mariadb|postgres|qdrant) .*\"${prefix}\"" "$SCRIPT"; then
        FAILED=$((FAILED + 1)); echo "FAIL: call site still passes ReplicaSet-hash prefix \"${prefix}\""
    else PASS=$((PASS + 1)); fi
done

echo "pass=$PASS fail=$FAILED"
[ "$FAILED" -eq 0 ]
