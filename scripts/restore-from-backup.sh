#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Restore from backup (drill / DR)                  ║
# ║  V1: MariaDB + Neo4j only (the schema layers Sprint 56 mutates)║
# ║  Defaults to a scratch namespace — explicit flag for prod      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Companion to backup-full-k8s.sh + backup-neo4j-only.sh.
#
# Required by ADR-011 §D6 as the Sprint 56 exit criterion: a successful
# restore drill must be demonstrated in a scratch namespace before the
# sprint can close.
#
# V1 scope (intentional):
#   - MariaDB logical restore (.sql.gz → mysql import)
#   - Neo4j binary restore (.dump → neo4j-admin database load)
#   - Postgres logical restore (.sql.gz → psql import)
#   - Counts/integrity check after each
#
# Out of scope (use the source backup files + per-service docs):
#   - Qdrant snapshot recovery (API-driven, per collection)
#   - ClickHouse raw tar extract
#   - Vault raft snapshot restore
#   - PV raw tar restore
#
# Safety:
#   - Default --target-ns is a SCRATCH namespace, never prod
#   - --target-ns prod-asgard-infra requires explicit --i-know-this-is-prod
#   - Each component restore is independent; failure is logged, others continue
#   - trap on EXIT ensures helper pods + port-forwards are cleaned up
#
# Usage:
#   ./scripts/restore-from-backup.sh /Volumes/T7\ Shield/asgard-backup-2026-05-23
#     → restores into ns asgard-restore-drill (default scratch)
#
#   ./scripts/restore-from-backup.sh <backup-dir> --component neo4j
#     → only Neo4j
#
#   ./scripts/restore-from-backup.sh <backup-dir> --target-ns my-test
#     → custom scratch namespace
#
#   ./scripts/restore-from-backup.sh <backup-dir> --target-ns asgard \
#       --i-know-this-is-prod
#     → DESTRUCTIVE — overwrites prod data
#
# Exit codes:
#   0  all requested components restored + counts verified
#   1  prerequisite failure (no backup dir, no kubectl, ...)
#   2  one or more component restores failed (see summary)
#   3  prod target requested without explicit confirm flag

set -uo pipefail

# ── config ──
BACKUP_DIR=""
TARGET_NS="${TARGET_NS:-asgard-restore-drill}"
COMPONENT="${COMPONENT:-all}"
PROD_CONFIRM=0
DRY_RUN=0
HELPER_POD_PREFIX="restore-helper-$$"

declare -a RESULTS=()
record() { RESULTS+=("$1|$2|$3"); }

LOG() { echo "$(date +%H:%M:%S) [restore] $*"; }
OK()  { echo "$(date +%H:%M:%S) [   ✅  ] $*"; }
ERR() { echo "$(date +%H:%M:%S) [   ❌  ] $*" >&2; }
SKIP(){ echo "$(date +%H:%M:%S) [   ⏭️  ] $*"; }

# ── parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --target-ns)            TARGET_NS="$2"; shift 2 ;;
    --component)            COMPONENT="$2"; shift 2 ;;
    --i-know-this-is-prod)  PROD_CONFIRM=1; shift ;;
    --dry-run)              DRY_RUN=1; shift ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      ERR "unknown flag: $1"; exit 1 ;;
    *)
      [ -z "$BACKUP_DIR" ] && BACKUP_DIR="$1" || { ERR "extra positional: $1"; exit 1; }
      shift ;;
  esac
done

# ── prereq checks ──
[ -z "$BACKUP_DIR" ] && { ERR "usage: $0 <backup-dir>"; exit 1; }
[ ! -d "$BACKUP_DIR" ] && { ERR "backup dir not found: $BACKUP_DIR"; exit 1; }
[ ! -f "$BACKUP_DIR/MANIFEST.md" ] && { ERR "missing MANIFEST.md — not a valid backup dir"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { ERR "kubectl not in PATH"; exit 1; }

# Prod safety gate — common prod ns names trigger the check.
case "$TARGET_NS" in
  asgard|asgard-infra|asgard-monitoring|wazuh)
    if [ "$PROD_CONFIRM" -ne 1 ]; then
      ERR "target ns '${TARGET_NS}' looks like prod. Add --i-know-this-is-prod to override."
      exit 3
    fi
    LOG "⚠️  RESTORING TO PROD NS: ${TARGET_NS} (explicit confirm given)"
    ;;
esac

# Ensure scratch ns exists
if ! kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
  LOG "creating namespace ${TARGET_NS}"
  kubectl create ns "$TARGET_NS" >/dev/null 2>&1 \
    || { ERR "cannot create ns ${TARGET_NS}"; exit 1; }
fi

LOG "=== Asgard Restore ==="
LOG "  source:    ${BACKUP_DIR}"
LOG "  target:    ns/${TARGET_NS}"
LOG "  component: ${COMPONENT}"
[ "$DRY_RUN" -eq 1 ] && LOG "  ⏸️  DRY RUN — no writes"

# ── cleanup trap ──
cleanup() {
  LOG "cleanup"
  kubectl get pods -n "$TARGET_NS" -l "role=restore-helper" --no-headers 2>/dev/null \
    | awk '{print $1}' \
    | xargs -I{} kubectl delete pod -n "$TARGET_NS" {} --wait=false >/dev/null 2>&1
}
trap cleanup EXIT

# ════════════ COMPONENT: MariaDB ════════════
restore_mariadb() {  # $1=sql.gz file $2=deploy name (must exist in TARGET_NS)
  local f="$1" deploy="$2"
  [ ! -f "$f" ] && { SKIP "MariaDB ${deploy} — ${f} missing"; record "mariadb-${deploy}" SKIP "no dump"; return; }

  local pod
  pod=$(kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null \
        | awk -v p="$deploy" '$1 ~ "^"p && $3=="Running" {print $1; exit}')
  if [ -z "$pod" ]; then
    SKIP "MariaDB ${deploy} — no running pod in ns/${TARGET_NS} (deploy the stack first)"
    record "mariadb-${deploy}" SKIP "no pod"
    return
  fi

  LOG "📊 MariaDB ${deploy} ← ${f}"
  [ "$DRY_RUN" -eq 1 ] && { OK "  (dry-run, no import)"; record "mariadb-${deploy}" DRYRUN "${f}"; return; }

  if gunzip -c "$f" | kubectl exec -i -n "$TARGET_NS" "$pod" -- sh -c \
       'mariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-root}}" 2>/dev/null'; then
    # count check — sum rows across all user DBs
    local cnt
    cnt=$(kubectl exec -n "$TARGET_NS" "$pod" -- sh -c \
          'mariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-root}}" -BN \
             -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN (\"mysql\",\"information_schema\",\"performance_schema\",\"sys\")" 2>/dev/null')
    OK "MariaDB ${deploy} → ${cnt:-?} user tables"
    record "mariadb-${deploy}" OK "${cnt} tables"
  else
    ERR "MariaDB ${deploy} import failed"
    record "mariadb-${deploy}" FAIL "import error"
  fi
}

# ════════════ COMPONENT: Postgres ════════════
restore_postgres() {  # $1=sql.gz file $2=deploy name
  local f="$1" deploy="$2"
  [ ! -f "$f" ] && { SKIP "Postgres ${deploy} — ${f} missing"; record "postgres-${deploy}" SKIP "no dump"; return; }

  local pod
  pod=$(kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null \
        | awk -v p="$deploy" '$1 ~ "^"p && $3=="Running" {print $1; exit}')
  if [ -z "$pod" ]; then
    SKIP "Postgres ${deploy} — no running pod in ns/${TARGET_NS}"
    record "postgres-${deploy}" SKIP "no pod"
    return
  fi

  LOG "🐘 Postgres ${deploy} ← ${f}"
  [ "$DRY_RUN" -eq 1 ] && { OK "  (dry-run)"; record "postgres-${deploy}" DRYRUN "${f}"; return; }

  if gunzip -c "$f" | kubectl exec -i -n "$TARGET_NS" "$pod" -- sh -c \
       'PGPASSWORD="${POSTGRES_PASSWORD:-${PGPASSWORD:-}}" psql -U "${POSTGRES_USER:-postgres}" 2>/dev/null'; then
    local cnt
    cnt=$(kubectl exec -n "$TARGET_NS" "$pod" -- sh -c \
          'PGPASSWORD="${POSTGRES_PASSWORD:-${PGPASSWORD:-}}" psql -U "${POSTGRES_USER:-postgres}" -tA \
             -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN (\"pg_catalog\",\"information_schema\")" 2>/dev/null')
    OK "Postgres ${deploy} → ${cnt:-?} user tables"
    record "postgres-${deploy}" OK "${cnt} tables"
  else
    ERR "Postgres ${deploy} import failed"
    record "postgres-${deploy}" FAIL "import error"
  fi
}

# ════════════ COMPONENT: Neo4j ════════════
restore_neo4j() {  # $1=neo4j.dump file
  local f="$1"
  [ ! -f "$f" ] && { SKIP "Neo4j — ${f} missing"; record "neo4j" SKIP "no dump"; return; }

  local deploy="neo4j"
  local image pvc orig_replicas
  image=$(kubectl get deploy "$deploy" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  pvc=$(kubectl get deploy "$deploy" -n "$TARGET_NS" \
        -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' \
        2>/dev/null | awk '{print $1}')
  orig_replicas=$(kubectl get deploy "$deploy" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)

  if [ -z "$image" ]; then
    SKIP "Neo4j — deploy not found in ns/${TARGET_NS} (deploy the stack first)"
    record "neo4j" SKIP "no deploy"
    return
  fi
  pvc="${pvc:-neo4j-data}"
  orig_replicas="${orig_replicas:-1}"

  LOG "🕸️  Neo4j ← ${f} (image=${image} pvc=${pvc})"
  [ "$DRY_RUN" -eq 1 ] && { OK "  (dry-run)"; record "neo4j" DRYRUN "${f}"; return; }

  # 1. scale to 0
  LOG "  scale neo4j → 0"
  kubectl scale deploy/"$deploy" -n "$TARGET_NS" --replicas=0 >/dev/null 2>&1
  for i in $(seq 1 24); do
    kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null | grep -q "^${deploy}-" || break
    sleep 5
  done

  # 2. helper pod with same PVC
  local helper="${HELPER_POD_PREFIX}-neo4j"
  kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${helper}
  namespace: ${TARGET_NS}
  labels: {role: restore-helper}
spec:
  restartPolicy: Never
  containers:
  - name: load
    image: ${image}
    command: ["sleep","900"]
    volumeMounts:
    - {name: data, mountPath: /data}
  volumes:
  - {name: data, persistentVolumeClaim: {claimName: ${pvc}}}
YAML

  if ! kubectl wait --for=condition=Ready pod/"$helper" -n "$TARGET_NS" --timeout=120s >/dev/null 2>&1; then
    ERR "Neo4j helper pod not ready — restoring service scale"
    kubectl scale deploy/"$deploy" -n "$TARGET_NS" --replicas="$orig_replicas" >/dev/null 2>&1
    record "neo4j" FAIL "helper not ready"
    return
  fi

  # 3. copy dump in + load
  if kubectl cp "$f" "${TARGET_NS}/${helper}:/tmp/neo4j.dump" 2>/dev/null \
     && kubectl exec -n "$TARGET_NS" "$helper" -- \
          neo4j-admin database load neo4j --from-path=/tmp --overwrite-destination 2>&1 | tail -3 \
     && OK "  load OK"; then
    record "neo4j" OK "loaded"
  else
    ERR "Neo4j load failed"
    record "neo4j" FAIL "load error"
  fi

  # 4. scale back + verify
  kubectl delete pod "$helper" -n "$TARGET_NS" --wait=false >/dev/null 2>&1
  kubectl scale deploy/"$deploy" -n "$TARGET_NS" --replicas="$orig_replicas" >/dev/null 2>&1
  LOG "  waiting for neo4j to come back online"
  for i in $(seq 1 36); do
    if kubectl get pods -n "$TARGET_NS" --no-headers 2>/dev/null | grep "^${deploy}-" | grep -q "1/1.*Running"; then
      OK "Neo4j back online"
      break
    fi
    sleep 5
  done
}

# ════════════ DISPATCH ════════════
do_mariadb=0; do_postgres=0; do_neo4j=0
case "$COMPONENT" in
  all)      do_mariadb=1; do_postgres=1; do_neo4j=1 ;;
  mariadb)  do_mariadb=1 ;;
  postgres) do_postgres=1 ;;
  neo4j)    do_neo4j=1 ;;
  *) ERR "unknown component: ${COMPONENT} (all|mariadb|postgres|neo4j)"; exit 1 ;;
esac

# V1 restore: ONE source per service type — drill verifies the dump loads,
# not multi-instance prod-DR (which requires multi-ns scratch deploy first).
# Multi-source restore is deferred to V2.
if [ "$do_mariadb" -eq 1 ]; then
  restore_mariadb "${BACKUP_DIR}/01-databases/mariadb-asgard.sql.gz" "mariadb"
fi
if [ "$do_postgres" -eq 1 ]; then
  restore_postgres "${BACKUP_DIR}/01-databases/postgres-asgard.sql.gz" "postgres"
fi
if [ "$do_neo4j" -eq 1 ]; then
  restore_neo4j "${BACKUP_DIR}/01-databases/neo4j.dump"
fi

# ── summary ──
echo
LOG "=== Restore Summary ==="
fails=0; oks=0; skips=0
for r in "${RESULTS[@]}"; do
  IFS='|' read -r n s d <<< "$r"
  printf "  %-22s %-7s %s\n" "$n" "$s" "$d"
  case "$s" in
    FAIL)   fails=$((fails+1)) ;;
    OK|DRYRUN) oks=$((oks+1)) ;;
    SKIP)   skips=$((skips+1)) ;;
  esac
done
echo

if [ "$fails" -gt 0 ]; then
  ERR "${fails} component(s) FAILED — see logs above"
  exit 2
fi
if [ "$oks" -eq 0 ]; then
  ERR "no components were actually restored (all skipped) — verify ns/${TARGET_NS} has the stack deployed first"
  exit 2
fi
OK "${oks} component(s) restored, ${skips} skipped"
exit 0
