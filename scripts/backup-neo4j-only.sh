#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🕸️  ASGARD — Neo4j-only backup (cheaper than full)           ║
# ║  Extracted from backup-full-k8s.sh for Sprint 56 schema       ║
# ║  migrations that only touch the graph layer.                  ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Use cases (per Sprint 56 plan):
#   - Pre-flight before Neo4j schema/label changes (POLE+O)
#   - Pre-flight before bulk :TOUCHED edge materialization
#   - Pre-flight before consolidation `Apply` mode
#
# What it does:
#   1. scale deploy/neo4j → 0 (Community edition needs whole DBMS offline)
#   2. launch helper pod mounting the neo4j-data PVC
#   3. neo4j-admin database dump → copy out → save to DEST
#   4. ALWAYS scale back to original replica count (trap on EXIT)
#
# Downtime: ~1.5 min. Caller is responsible for maintenance window.
#
# Usage:
#   ./scripts/backup-neo4j-only.sh                     # default DEST + tag
#   DEST=/tmp/neo4j-backup ./scripts/backup-neo4j-only.sh
#   TAG=pre-pole-o ./scripts/backup-neo4j-only.sh      # appended to filename
#   ./scripts/backup-neo4j-only.sh --dry-run           # check prereqs, no scale
#   ./scripts/backup-neo4j-only.sh --verify <dump>     # load dump into scratch pod
#
# Exit codes:
#   0  success (dump file written, non-empty, service restored)
#   1  prerequisite failure (no kubectl, no deploy, no PVC, T7 missing)
#   2  dump failed
#   3  copy-out failed or empty dump
#   4  service restore failed (CRITICAL — Neo4j may be down)

set -uo pipefail

# ── config ──
NS="${NS:-asgard-infra}"
DEPLOY="${DEPLOY:-neo4j}"
HELPER_POD="${HELPER_POD:-neo4j-backup-helper-$$}"
DB_NAME="${DB_NAME:-neo4j}"
DATE=$(date +%Y-%m-%d)
TS=$(date +%Y-%m-%d_%H%M%S)
TAG="${TAG:-}"
DEST_DEFAULT="/Volumes/T7 Shield/asgard-neo4j-backup-${DATE}"
DEST="${DEST:-$DEST_DEFAULT}"
WAIT_SCALE_DOWN_S="${WAIT_SCALE_DOWN_S:-120}"
WAIT_HELPER_READY_S="${WAIT_HELPER_READY_S:-120}"
WAIT_SCALE_UP_S="${WAIT_SCALE_UP_S:-180}"
DRY_RUN=0
VERIFY_MODE=0
VERIFY_FILE=""

# ── logging ──
LOG() { echo "$(date +%H:%M:%S) [neo4j-bk] $*"; }
OK()  { echo "$(date +%H:%M:%S) [   ✅  ] $*"; }
ERR() { echo "$(date +%H:%M:%S) [   ❌  ] $*" >&2; }
WARN(){ echo "$(date +%H:%M:%S) [   ⚠️  ] $*" >&2; }

# ── parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --verify)  VERIFY_MODE=1; VERIFY_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) ERR "unknown arg: $1"; exit 1 ;;
  esac
done

# ── prereq checks (exit 1 on any miss) ──
command -v kubectl >/dev/null 2>&1 || { ERR "kubectl not in PATH"; exit 1; }

if [ "$VERIFY_MODE" -eq 1 ]; then
  [ -f "$VERIFY_FILE" ] || { ERR "--verify needs a dump file path"; exit 1; }
fi

ORIG_REPLICAS=""
PVC=""
IMAGE=""

discover_deploy() {
  IMAGE=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  PVC=$(kubectl get deploy "$DEPLOY" -n "$NS" \
        -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' \
        2>/dev/null | awk '{print $1}')
  ORIG_REPLICAS=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)

  [ -z "$IMAGE" ] && { ERR "deploy/${DEPLOY} not found in ns/${NS}"; exit 1; }
  PVC="${PVC:-neo4j-data}"
  ORIG_REPLICAS="${ORIG_REPLICAS:-1}"
  LOG "discovered: image=$IMAGE pvc=$PVC orig_replicas=$ORIG_REPLICAS"
}

# ── trap: ALWAYS try to restore service + cleanup helper ──
cleanup() {
  local rc=$?
  LOG "cleanup (exit=${rc})"
  kubectl delete pod "$HELPER_POD" -n "$NS" --wait=false >/dev/null 2>&1 || true
  if [ -n "$ORIG_REPLICAS" ] && [ "$DRY_RUN" -eq 0 ] && [ "$VERIFY_MODE" -eq 0 ]; then
    kubectl scale deploy/"$DEPLOY" -n "$NS" --replicas="$ORIG_REPLICAS" >/dev/null 2>&1
    LOG "scaled deploy/${DEPLOY} back to ${ORIG_REPLICAS}"
    local back_up=0
    for i in $(seq 1 $((WAIT_SCALE_UP_S / 5))); do
      if kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep "^${DEPLOY}-" | grep -q "1/1.*Running"; then
        OK "neo4j back online"
        back_up=1
        break
      fi
      sleep 5
    done
    if [ "$back_up" -eq 0 ]; then
      ERR "neo4j did NOT come back online within ${WAIT_SCALE_UP_S}s — CHECK MANUALLY"
      exit 4
    fi
  fi
}
trap cleanup EXIT

# ════════════ MODES ════════════

verify_dump() {
  LOG "=== Verify dump: ${VERIFY_FILE} ==="
  discover_deploy
  [ -s "$VERIFY_FILE" ] || { ERR "dump file empty"; exit 3; }
  local sz; sz=$(du -h "$VERIFY_FILE" | cut -f1)
  LOG "dump size: $sz"

  # Spin scratch pod with empty volume, load dump, print summary. No impact on prod Neo4j.
  local scratch="neo4j-verify-$$"
  LOG "launching scratch pod ${scratch} (read-only verify, no PVC mount)"
  kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata: {name: ${scratch}, namespace: ${NS}}
spec:
  restartPolicy: Never
  containers:
  - name: verify
    image: ${IMAGE}
    command: ["sleep","600"]
    volumeMounts:
    - {name: scratch, mountPath: /data}
  volumes:
  - {name: scratch, emptyDir: {}}
YAML
  kubectl wait --for=condition=Ready pod/"$scratch" -n "$NS" --timeout=120s >/dev/null 2>&1 \
    || { ERR "scratch pod not ready"; kubectl delete pod "$scratch" -n "$NS" --wait=false >/dev/null 2>&1; exit 3; }

  kubectl cp "$VERIFY_FILE" "${NS}/${scratch}:/tmp/${DB_NAME}.dump" 2>/dev/null \
    || { ERR "cp dump to scratch failed"; kubectl delete pod "$scratch" -n "$NS" --wait=false >/dev/null 2>&1; exit 3; }

  if kubectl exec -n "$NS" "$scratch" -- neo4j-admin database load "$DB_NAME" --from-path=/tmp --overwrite-destination 2>&1 | tail -5; then
    OK "dump loads cleanly (load-test passed)"
    kubectl delete pod "$scratch" -n "$NS" --wait=false >/dev/null 2>&1
    exit 0
  else
    ERR "dump FAILED to load — backup is corrupt"
    kubectl delete pod "$scratch" -n "$NS" --wait=false >/dev/null 2>&1
    exit 3
  fi
}

dry_run() {
  LOG "=== DRY RUN — no scale, no dump ==="
  discover_deploy
  case "$DEST" in
    /Volumes/T7*)
      if [ ! -d "$(dirname "$DEST")" ]; then
        ERR "T7 not mounted — $(dirname "$DEST") missing"
        exit 1
      fi
      ;;
  esac
  mkdir -p "$DEST" 2>/dev/null || { ERR "cannot create DEST=$DEST"; exit 1; }
  touch "$DEST/.write-test" && rm "$DEST/.write-test" || { ERR "DEST not writable"; exit 1; }
  OK "prereqs OK — ready to run without --dry-run"
  ORIG_REPLICAS=""   # disable trap restore
  exit 0
}

[ "$VERIFY_MODE" -eq 1 ] && verify_dump
[ "$DRY_RUN" -eq 1 ] && dry_run

# ════════════ MAIN BACKUP ════════════

LOG "=== Asgard Neo4j-only backup ${TS} ==="
LOG "destination: ${DEST}"

case "$DEST" in
  /Volumes/T7*)
    [ -d "$(dirname "$DEST")" ] || { ERR "T7 not mounted"; exit 1; }
    ;;
esac
mkdir -p "$DEST" || { ERR "cannot create DEST=$DEST"; exit 1; }

OUT_BASENAME="${DB_NAME}${TAG:+-${TAG}}.dump"
OUT="${DEST}/${OUT_BASENAME}"

discover_deploy

# 1. scale down
LOG "scaling deploy/${DEPLOY} → 0"
kubectl scale deploy/"$DEPLOY" -n "$NS" --replicas=0 >/dev/null 2>&1
local_done=0
for i in $(seq 1 $((WAIT_SCALE_DOWN_S / 5))); do
  kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -q "^${DEPLOY}-" || { local_done=1; break; }
  sleep 5
done
[ "$local_done" -eq 1 ] || { ERR "neo4j pods did not terminate within ${WAIT_SCALE_DOWN_S}s"; exit 2; }
OK "deploy scaled to 0"

# 2. helper pod
LOG "launching helper pod ${HELPER_POD}"
kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata: {name: ${HELPER_POD}, namespace: ${NS}, labels: {role: backup-helper}}
spec:
  restartPolicy: Never
  containers:
  - name: dump
    image: ${IMAGE}
    command: ["sleep","900"]
    volumeMounts:
    - {name: data, mountPath: /data}
  volumes:
  - {name: data, persistentVolumeClaim: {claimName: ${PVC}}}
YAML

kubectl wait --for=condition=Ready pod/"$HELPER_POD" -n "$NS" --timeout="${WAIT_HELPER_READY_S}s" >/dev/null 2>&1 \
  || { ERR "helper pod not ready within ${WAIT_HELPER_READY_S}s"; exit 2; }
OK "helper pod ready"

# 3. dump
LOG "running neo4j-admin database dump ${DB_NAME}"
if kubectl exec -n "$NS" "$HELPER_POD" -- \
     neo4j-admin database dump "$DB_NAME" --to-path=/tmp --overwrite-destination >/dev/null 2>&1; then
  OK "dump created in helper:/tmp/${DB_NAME}.dump"
else
  ERR "neo4j-admin dump failed"
  exit 2
fi

# 4. copy out
LOG "copying dump → ${OUT}"
if kubectl exec -n "$NS" "$HELPER_POD" -- cat "/tmp/${DB_NAME}.dump" > "$OUT" 2>/dev/null && [ -s "$OUT" ]; then
  SIZE=$(du -h "$OUT" | cut -f1)
  OK "dump → ${OUT_BASENAME} (${SIZE})"
else
  ERR "copy-out failed or empty"
  exit 3
fi

# 5. manifest
cat > "${DEST}/MANIFEST-${OUT_BASENAME}.md" <<EOF
# Neo4j-only backup — ${TS}

- File: \`${OUT_BASENAME}\`
- Size: ${SIZE}
- Source: ns/${NS} deploy/${DEPLOY} pvc/${PVC}
- Image: ${IMAGE}
- DB: ${DB_NAME}
- Host: $(hostname)
- Tag: ${TAG:-(none)}
- Downtime: from $(date) — scale-back follows in cleanup trap

## Restore
\`\`\`
# 1. stop neo4j
kubectl scale deploy/neo4j -n ${NS} --replicas=0

# 2. launch helper pod mounting neo4j-data PVC (same image: ${IMAGE})
# 3. kubectl cp ${OUT_BASENAME} <ns>/<helper>:/tmp/${DB_NAME}.dump
# 4. kubectl exec ... neo4j-admin database load ${DB_NAME} --from-path=/tmp --overwrite-destination
# 5. delete helper, scale neo4j back to 1
\`\`\`

## Verify this dump
\`\`\`
./scripts/backup-neo4j-only.sh --verify ${OUT}
\`\`\`
EOF
OK "manifest → MANIFEST-${OUT_BASENAME}.md"

LOG "=== complete ==="
# trap cleanup runs now: deletes helper, scales back to ORIG_REPLICAS