#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Full Backup (K8s-aware) → T7 external            ║
# ║  All databases + PVs, for rollback / disaster recovery        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Replaces the docker-compose-era scripts/backup.sh (which used
# `docker exec asgard_neo4j` container names that don't exist in the
# current OrbStack K8s deployment). Discovers pods dynamically.
#
# Usage:
#   ./scripts/backup-full-k8s.sh                 # full backup to T7
#   DEST=/some/path ./scripts/backup-full-k8s.sh # custom dest
#
# Strategy:
#   - SQL stores  → logical dumps (online-safe, rollback-grade)
#   - Neo4j       → STOP DATABASE → neo4j-admin dump → START (brief offline)
#   - Qdrant      → snapshot API via port-forward
#   - ClickHouse  → raw data tar (observability data, best-effort)
#   - RabbitMQ    → definitions.json
#   - Other PVs   → raw tar via `kubectl exec tar` (best-effort, skipped if no tar)
#   - Vault       → raft snapshot if available, else PVC tar (unseal keys NOT included)
#   - K8s         → PVC/PV definitions + per-namespace manifests
#
# Every step is fault-tolerant: failures are logged, never abort the run.
set -uo pipefail

TS=$(date +%Y-%m-%d_%H%M%S)
DATE=$(date +%Y-%m-%d)
DEST="${DEST:-/Volumes/T7 Shield/asgard-backup-${DATE}}"
LOG() { echo "$(date +%H:%M:%S) [BACKUP] $*"; }
OK()  { echo "$(date +%H:%M:%S) [  ✅  ] $*"; }
ERR() { echo "$(date +%H:%M:%S) [  ❌  ] $*" >&2; }
SKIP(){ echo "$(date +%H:%M:%S) [  ⏭️  ] $*"; }

declare -a RESULTS=()
record() { RESULTS+=("$1|$2|$3"); }   # name|status|detail

mkdir -p "$DEST"/{01-databases,02-snapshots,03-pv-raw,04-k8s,05-vault}
LOG "=== Asgard Full Backup ${TS} ==="
LOG "Destination: ${DEST}"
echo

# Resolve current pod name by namespace + label-ish name prefix
pod_for() {  # $1=ns $2=name-prefix
  kubectl get pods -n "$1" --no-headers 2>/dev/null \
    | awk -v p="$2" '$1 ~ "^"p && $3=="Running" {print $1; exit}'
}

# ── 1. MariaDB (logical) ──
backup_mariadb() {  # $1=ns $2=podprefix $3=outfile
  local ns="$1" pod; pod=$(pod_for "$ns" "$2")
  [ -z "$pod" ] && { SKIP "MariaDB ${ns}/$2 — no running pod"; record "mariadb-${ns}" SKIP "no pod"; return; }
  LOG "📊 MariaDB ${ns}/${pod} → $3"
  # NOTE: mariadb:11 image ships `mariadb-dump`, not `mysqldump` (no symlink)
  if kubectl exec -n "$ns" "$pod" -- sh -c \
      'mariadb-dump --all-databases --single-transaction --routines --triggers --events \
       -uroot -p"${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-root}}" 2>/dev/null' \
      | gzip > "${DEST}/01-databases/$3"; then
    local sz; sz=$(du -h "${DEST}/01-databases/$3" | cut -f1)
    [ -s "${DEST}/01-databases/$3" ] && { OK "MariaDB ${ns} → $3 ($sz)"; record "mariadb-${ns}" OK "$sz"; } \
      || { ERR "MariaDB ${ns} dump empty"; record "mariadb-${ns}" FAIL "empty"; }
  else ERR "MariaDB ${ns} dump failed"; record "mariadb-${ns}" FAIL "exec error"; fi
}

# ── 2. PostgreSQL (logical) ──
backup_postgres() {  # $1=ns $2=podprefix $3=outfile
  local ns="$1" pod; pod=$(pod_for "$ns" "$2")
  [ -z "$pod" ] && { SKIP "Postgres ${ns}/$2 — no running pod"; record "postgres-${ns}-$2" SKIP "no pod"; return; }
  LOG "🐘 Postgres ${ns}/${pod} → $3"
  if kubectl exec -n "$ns" "$pod" -- sh -c \
      'PGPASSWORD="${POSTGRES_PASSWORD:-${PGPASSWORD:-}}" pg_dumpall -U "${POSTGRES_USER:-postgres}" 2>/dev/null' \
      | gzip > "${DEST}/01-databases/$3"; then
    local sz; sz=$(du -h "${DEST}/01-databases/$3" | cut -f1)
    [ -s "${DEST}/01-databases/$3" ] && { OK "Postgres → $3 ($sz)"; record "postgres-$2" OK "$sz"; } \
      || { ERR "Postgres $2 dump empty"; record "postgres-$2" FAIL "empty"; }
  else ERR "Postgres $2 dump failed"; record "postgres-$2" FAIL "exec error"; fi
}

# ── 3. Neo4j (binary dump) ──
# Community edition: STOP/START DATABASE is Enterprise-only, so the whole DBMS
# must be offline. We scale the deployment to 0, dump via a helper pod that
# mounts the same (RWO) PVC, then scale back. Brief Neo4j downtime (~1-2 min).
backup_neo4j() {
  local ns="asgard-infra" deploy="neo4j"
  local img; img=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  local pvc; pvc=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null | awk '{print $1}')
  [ -z "$img" ] && { SKIP "Neo4j — deploy not found"; record "neo4j" SKIP "no deploy"; return; }
  pvc="${pvc:-neo4j-data}"
  LOG "🕸️  Neo4j — scale 0 → helper dump → scale 1 (img=$img pvc=$pvc)"
  local orig; orig=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null); orig="${orig:-1}"
  kubectl scale deploy/"$deploy" -n "$ns" --replicas=0 >/dev/null 2>&1
  for i in $(seq 1 24); do kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -q "^${deploy}-" || break; sleep 5; done
  kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata: {name: neo4j-backup-helper, namespace: ${ns}}
spec:
  restartPolicy: Never
  containers:
  - {name: dump, image: ${img}, command: ["sleep","900"], volumeMounts: [{name: data, mountPath: /data}]}
  volumes:
  - {name: data, persistentVolumeClaim: {claimName: ${pvc}}}
YAML
  kubectl wait --for=condition=Ready pod/neo4j-backup-helper -n "$ns" --timeout=120s >/dev/null 2>&1
  kubectl exec -n "$ns" neo4j-backup-helper -- neo4j-admin database dump neo4j --to-path=/tmp --overwrite-destination >/dev/null 2>&1 \
    && OK "  dump complete" || ERR "  dump failed"
  if kubectl exec -n "$ns" neo4j-backup-helper -- cat /tmp/neo4j.dump > "${DEST}/01-databases/neo4j.dump" 2>/dev/null && [ -s "${DEST}/01-databases/neo4j.dump" ]; then
    local sz; sz=$(du -h "${DEST}/01-databases/neo4j.dump" | cut -f1); OK "Neo4j → neo4j.dump ($sz)"; record "neo4j" OK "$sz"
  else ERR "Neo4j copy-out failed"; record "neo4j" FAIL "copyout"; fi
  kubectl delete pod neo4j-backup-helper -n "$ns" --wait=false >/dev/null 2>&1
  kubectl scale deploy/"$deploy" -n "$ns" --replicas="$orig" >/dev/null 2>&1   # ALWAYS restore service
  for i in $(seq 1 36); do kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep "^${deploy}-" | grep -q "1/1 .*Running" && { OK "  neo4j back online"; break; }; sleep 5; done
}

# ── 4. Qdrant (snapshot API via port-forward) ──
backup_qdrant() {  # $1=ns $2=podprefix $3=subdir $4=localport
  local ns="$1" pod; pod=$(pod_for "$ns" "$2")
  [ -z "$pod" ] && { SKIP "Qdrant ${ns} — no pod"; record "qdrant-${ns}" SKIP "no pod"; return; }
  local lp="$4"
  LOG "🔍 Qdrant ${ns}/${pod} (pf :$lp)"
  kubectl port-forward -n "$ns" "pod/$pod" "${lp}:6333" >/dev/null 2>&1 &
  local pf=$!; sleep 4
  local cols; cols=$(curl -sf "http://localhost:${lp}/collections" 2>/dev/null \
    | python3 -c "import sys,json;[print(c['name']) for c in json.load(sys.stdin)['result']['collections']]" 2>/dev/null)
  if [ -z "$cols" ]; then SKIP "Qdrant ${ns} — no collections / unreachable"; record "qdrant-${ns}" SKIP "no collections"; kill $pf 2>/dev/null; return; fi
  mkdir -p "${DEST}/02-snapshots/$3"
  local n=0
  for c in $cols; do
    local snap; snap=$(curl -sf -X POST "http://localhost:${lp}/collections/${c}/snapshots" 2>/dev/null \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['name'])" 2>/dev/null)
    [ -z "$snap" ] && { ERR "  ${c}: snapshot create failed"; continue; }
    if curl -sf "http://localhost:${lp}/collections/${c}/snapshots/${snap}" -o "${DEST}/02-snapshots/$3/${c}.snapshot" 2>/dev/null; then
      OK "  ${c} → ${c}.snapshot"; n=$((n+1))
    else ERR "  ${c}: download failed"; fi
  done
  kill $pf 2>/dev/null
  record "qdrant-${ns}" OK "${n} collections"
}

# ── 5. ClickHouse (raw tar) + RabbitMQ (definitions) ──
backup_clickhouse() {
  local ns="asgard" pod; pod=$(pod_for "$ns" "laminar-clickhouse")
  [ -z "$pod" ] && { SKIP "ClickHouse — no pod"; record "clickhouse" SKIP "no pod"; return; }
  LOG "📈 ClickHouse ${pod} (raw tar)"
  if kubectl exec -n "$ns" "$pod" -- tar czf - -C /var/lib/clickhouse . 2>/dev/null > "${DEST}/01-databases/clickhouse-data.tar.gz" && [ -s "${DEST}/01-databases/clickhouse-data.tar.gz" ]; then
    local sz; sz=$(du -h "${DEST}/01-databases/clickhouse-data.tar.gz" | cut -f1)
    OK "ClickHouse → clickhouse-data.tar.gz ($sz)"; record "clickhouse" OK "$sz"
  else ERR "ClickHouse tar failed"; record "clickhouse" FAIL "tar error"; fi
}
backup_rabbitmq() {
  local ns="asgard" pod; pod=$(pod_for "$ns" "laminar-rabbitmq")
  [ -z "$pod" ] && { SKIP "RabbitMQ — no pod"; record "rabbitmq" SKIP "no pod"; return; }
  LOG "🐰 RabbitMQ ${pod} (definitions)"
  if kubectl exec -n "$ns" "$pod" -- rabbitmqctl export_definitions /tmp/defs.json 2>/dev/null \
     && kubectl exec -n "$ns" "$pod" -- cat /tmp/defs.json > "${DEST}/01-databases/rabbitmq-definitions.json" 2>/dev/null \
     && [ -s "${DEST}/01-databases/rabbitmq-definitions.json" ]; then
    OK "RabbitMQ → rabbitmq-definitions.json"; record "rabbitmq" OK "defs"
  else ERR "RabbitMQ export failed"; record "rabbitmq" FAIL "export error"; fi
}

# ── 6. Generic raw PV tar (find pod+mountPath for a PVC) ──
backup_pv_raw() {  # $1=ns $2=pvc $3=outname
  local ns="$1" pvc="$2"
  read -r pod mp < <(kubectl get pods -n "$ns" -o json 2>/dev/null | python3 -c "
import sys,json
ns_pvc='$pvc'
data=json.load(sys.stdin)
for p in data['items']:
    if p.get('status',{}).get('phase')!='Running': continue
    vols={v['name']:v for v in p['spec'].get('volumes',[])}
    claim={n:v for n,v in vols.items() if v.get('persistentVolumeClaim',{}).get('claimName')==ns_pvc}
    if not claim: continue
    for c in p['spec']['containers']:
        for m in c.get('volumeMounts',[]):
            if m['name'] in claim:
                print(p['metadata']['name'], m['mountPath']); sys.exit()
" 2>/dev/null)
  [ -z "${pod:-}" ] && { SKIP "PV ${pvc} — no mounting pod"; record "pv-${pvc}" SKIP "no pod"; return; }
  LOG "💾 PV ${pvc} from ${pod}:${mp} → $3"
  if kubectl exec -n "$ns" "$pod" -- tar czf - -C "$mp" . 2>/dev/null > "${DEST}/03-pv-raw/$3" && [ -s "${DEST}/03-pv-raw/$3" ]; then
    local sz; sz=$(du -h "${DEST}/03-pv-raw/$3" | cut -f1)
    OK "PV ${pvc} → $3 ($sz)"; record "pv-${pvc}" OK "$sz"
  else ERR "PV ${pvc} tar failed (no tar in image?)"; record "pv-${pvc}" FAIL "tar error"; fi
}

# ── 6b. MinIO (distroless image has no `tar`) ──
# Same pattern as Neo4j: scale deploy to 0, mount the RWO PVC in a busybox helper
# (which HAS tar+gzip), stream out, scale back. Brief MinIO downtime (~30-60s).
backup_minio() {
  local ns="asgard-infra" deploy="minio" pvc="minio-pvc" out="minio.tar.gz"
  kubectl get deploy "$deploy" -n "$ns" >/dev/null 2>&1 || { SKIP "MinIO — deploy not found"; record "pv-minio-pvc" SKIP "no deploy"; return; }
  pvc=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null | awk '{print $1}'); pvc="${pvc:-minio-pvc}"
  LOG "💾 MinIO — scale 0 → busybox helper tar → scale 1 (pvc=$pvc)"
  local orig; orig=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null); orig="${orig:-1}"
  kubectl scale deploy/"$deploy" -n "$ns" --replicas=0 >/dev/null 2>&1
  for i in $(seq 1 24); do kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -q "^${deploy}-" || break; sleep 5; done
  kubectl apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata: {name: minio-backup-helper, namespace: ${ns}}
spec:
  restartPolicy: Never
  containers:
  - {name: tar, image: busybox:1.36, command: ["sleep","900"], volumeMounts: [{name: data, mountPath: /data}]}
  volumes:
  - {name: data, persistentVolumeClaim: {claimName: ${pvc}}}
YAML
  kubectl wait --for=condition=Ready pod/minio-backup-helper -n "$ns" --timeout=120s >/dev/null 2>&1
  if kubectl exec -n "$ns" minio-backup-helper -- sh -c 'tar cf - -C /data . | gzip' 2>/dev/null > "${DEST}/03-pv-raw/$out" && [ -s "${DEST}/03-pv-raw/$out" ]; then
    local sz; sz=$(du -h "${DEST}/03-pv-raw/$out" | cut -f1); OK "MinIO → $out ($sz)"; record "pv-minio-pvc" OK "$sz"
  else ERR "MinIO helper tar failed"; record "pv-minio-pvc" FAIL "helper tar"; fi
  kubectl delete pod minio-backup-helper -n "$ns" --wait=false >/dev/null 2>&1
  kubectl scale deploy/"$deploy" -n "$ns" --replicas="$orig" >/dev/null 2>&1   # ALWAYS restore service
  for i in $(seq 1 36); do kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep "^${deploy}-" | grep -q "1/1 .*Running" && { OK "  minio back online"; break; }; sleep 5; done
}

# ── 7. Vault (raft snapshot, no unseal keys) ──
backup_vault() {
  local ns="asgard" pod; pod=$(pod_for "$ns" "fafnir-vault")
  [ -z "$pod" ] && { SKIP "Vault — no pod"; record "vault" SKIP "no pod"; return; }
  LOG "🔐 Vault ${pod} — raft snapshot (unseal keys NOT included — manual)"
  if kubectl exec -n "$ns" "$pod" -- sh -c 'vault operator raft snapshot save /tmp/vault.snap 2>/dev/null' \
     && kubectl exec -n "$ns" "$pod" -- cat /tmp/vault.snap > "${DEST}/05-vault/vault-raft.snap" 2>/dev/null \
     && [ -s "${DEST}/05-vault/vault-raft.snap" ]; then
    OK "Vault → vault-raft.snap"; record "vault" OK "raft snapshot"
    kubectl exec -n "$ns" "$pod" -- rm -f /tmp/vault.snap 2>/dev/null
  else
    SKIP "Vault raft snapshot unavailable (sealed/not-raft) — see 05-vault/MANUAL.md"
    record "vault" MANUAL "raft unavailable"
  fi
  cat > "${DEST}/05-vault/MANUAL.md" <<EOF
# Vault backup — manual step required
Unseal keys / root token are NOT in this backup (sensitive).
To complete rollback capability, securely store init-keys.json out-of-band.
If raft snapshot present: \`vault operator raft snapshot restore vault-raft.snap\`
EOF
}

# ── 8. K8s manifests + PVC/PV definitions ──
backup_k8s() {
  LOG "☸️  K8s definitions"
  kubectl get pvc,pv -A -o yaml > "${DEST}/04-k8s/pvc-pv-definitions.yaml" 2>/dev/null && OK "  PVC/PV definitions"
  for ns in asgard asgard-infra asgard-monitoring wazuh; do
    kubectl get all,configmap,secret,ingress -n "$ns" -o yaml > "${DEST}/04-k8s/manifests-${ns}.yaml" 2>/dev/null \
      && OK "  ns/${ns} manifests" || SKIP "  ns/${ns} (none)"
  done
  helm list -A -o yaml > "${DEST}/04-k8s/helm-releases.yaml" 2>/dev/null && OK "  helm releases"
  record "k8s-manifests" OK "definitions"
}

# ════════════ RUN ════════════
backup_mariadb  asgard       "mariadb-67c"        "mariadb-asgard.sql.gz"
backup_mariadb  asgard-infra "mariadb-585"        "mariadb-infra.sql.gz"
backup_postgres asgard       "postgres-64"        "postgres-asgard.sql.gz"
backup_postgres asgard-infra "postgres-66"        "postgres-infra.sql.gz"
backup_postgres asgard       "laminar-postgres"   "postgres-laminar.sql.gz"
backup_neo4j
backup_qdrant   asgard       "qdrant-cf"   "qdrant-asgard" 16333
backup_qdrant   asgard-infra "qdrant-5f"   "qdrant-infra"  16334
backup_clickhouse
backup_rabbitmq
backup_pv_raw   asgard       "laminar-quickwit-data" "quickwit.tar.gz"
backup_minio
backup_pv_raw   asgard       "bifrost-data-pvc"      "bifrost-data.tar.gz"
backup_pv_raw   asgard       "eir-sites-data"        "eir-sites.tar.gz"
backup_pv_raw   asgard       "forseti-data"          "forseti-data.tar.gz"
backup_pv_raw   asgard       "mjolnir-data"          "mjolnir-data.tar.gz"
backup_pv_raw   asgard       "mimir-medical-docs"    "mimir-medical-docs.tar.gz"
backup_vault
backup_k8s

# ── MANIFEST ──
{
  echo "# Asgard Full Backup Manifest — ${TS}"
  echo
  echo "Destination: \`${DEST}\`"
  echo "Host: $(hostname)  |  Created: $(date)"
  echo
  echo "## Results"
  echo "| Component | Status | Detail |"
  echo "|-----------|--------|--------|"
  for r in "${RESULTS[@]}"; do IFS='|' read -r n s d <<< "$r"; echo "| $n | $s | $d |"; done
  echo
  echo "## NOT included (by design)"
  echo "- Source code repos (~/Developer, 150G) — separate concern"
  echo "- tyr-* PVs (wazuh SIEM, ~70G) — already on T7 by design (Tyr PVC-on-T7)"
  echo "- asgard-infra/mariadb-data PVC is Terminating (mid-migration) — logical dump captured instead"
  echo "- Vault unseal keys / root token — must be stored out-of-band (see 05-vault/MANUAL.md)"
  echo
  echo "## Restore order (disaster recovery)"
  echo "1. Recreate K8s cluster + apply 04-k8s manifests + PVC/PV definitions"
  echo "2. MariaDB: \`gunzip -c X.sql.gz | mysql\`  (per namespace)"
  echo "3. Postgres: \`gunzip -c X.sql.gz | psql -U postgres\`"
  echo "4. Neo4j: STOP DATABASE neo4j; neo4j-admin database load neo4j --from-path=. --overwrite-destination; START DATABASE neo4j"
  echo "5. Qdrant: snapshot recovery API per collection (02-snapshots/)"
  echo "6. ClickHouse/Quickwit/others: extract raw tars into fresh PVCs"
  echo "7. Vault: raft snapshot restore + unseal with out-of-band keys"
} > "${DEST}/MANIFEST.md"

echo
LOG "=== Backup complete → ${DEST} ==="
ls -lhR "${DEST}" 2>/dev/null | grep -vE "^total|^d" | grep -E "\.(gz|dump|snap|json|yaml|md)" | awk '{print $5, $9}'
echo
LOG "=== Summary ==="
for r in "${RESULTS[@]}"; do IFS='|' read -r n s d <<< "$r"; printf "  %-22s %-7s %s\n" "$n" "$s" "$d"; done
