#!/usr/bin/env bash
# k8s-aware full backup — successor to the compose-era backup.sh (which now
# skips everything because containers run under k8s as k8s_* names).
#
# Covers: MariaDB x2 (asgard, asgard-infra) + legacy mimir_mariadb,
# PostgreSQL x2, Qdrant snapshots (both namespaces, via ClusterIP from inside
# the VM), Neo4j manifest (graph is regenerable from import artifacts —
# consistent offline dump needs a stop, never during freeze), plus the
# ClinicalKB source artifacts that cannot be regenerated for free.
#
# Usage: ./scripts/backup-k8s.sh [output-base]
set -uo pipefail

BASE="${1:-/Volumes/T7 Shield/asgard-backups}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT="$BASE/full-$STAMP"
mkdir -p "$OUT"
FAIL=0
log() { echo "$(date +%H:%M:%S) [BACKUP] $*"; }

dump_mariadb() {
  local cname="$1" label="$2"
  local c
  c=$(docker ps --format '{{.Names}}' | grep "^$cname" | head -1)
  if [ -z "$c" ]; then log "SKIP $label (container not found)"; FAIL=1; return; fi
  log "MariaDB $label ..."
  if docker exec "$c" sh -c 'mariadb-dump -uroot -p"${MYSQL_ROOT_PASSWORD:-$MARIADB_ROOT_PASSWORD}" --all-databases --single-transaction 2>/dev/null || mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-$MARIADB_ROOT_PASSWORD}" --all-databases --single-transaction' | gzip > "$OUT/mariadb-$label.sql.gz"; then
    log "OK  mariadb-$label.sql.gz ($(du -h "$OUT/mariadb-$label.sql.gz" | cut -f1))"
  else log "FAIL mariadb $label"; FAIL=1; fi
}

dump_postgres() {
  local cname="$1" label="$2"
  local c
  c=$(docker ps --format '{{.Names}}' | grep "^$cname" | head -1)
  if [ -z "$c" ]; then log "SKIP $label (container not found)"; FAIL=1; return; fi
  log "PostgreSQL $label ..."
  if docker exec "$c" sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' | gzip > "$OUT/postgres-$label.sql.gz"; then
    log "OK  postgres-$label.sql.gz ($(du -h "$OUT/postgres-$label.sql.gz" | cut -f1))"
  else log "FAIL postgres $label"; FAIL=1; fi
}

qdrant_snapshots() {
  local ip="$1" label="$2"
  log "Qdrant $label ($ip) ..."
  local cols
  cols=$(docker run --rm --net=host busybox wget -qO- "http://$ip:6333/collections" 2>/dev/null | python3 -c "import sys,json; print(' '.join(c['name'] for c in json.load(sys.stdin)['result']['collections']))" 2>/dev/null)
  if [ -z "$cols" ]; then log "FAIL qdrant $label unreachable"; FAIL=1; return; fi
  for col in $cols; do
    local snap
    snap=$(docker run --rm --net=host busybox wget -qO- --post-data='' "http://$ip:6333/collections/$col/snapshots" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['name'])" 2>/dev/null)
    if [ -n "$snap" ]; then
      docker run --rm --net=host busybox wget -qO- "http://$ip:6333/collections/$col/snapshots/$snap" > "$OUT/qdrant-$label-$col.snapshot" 2>/dev/null \
        && log "OK  qdrant-$label-$col.snapshot ($(du -h "$OUT/qdrant-$label-$col.snapshot" | cut -f1))" \
        || { log "FAIL download qdrant $label/$col"; FAIL=1; }
    else log "FAIL snapshot qdrant $label/$col"; FAIL=1; fi
  done
}

log "Target: $OUT"

dump_mariadb "k8s_mariadb_mariadb.*_asgard_" "asgard"
dump_mariadb "k8s_mariadb_mariadb.*_asgard-infra_" "asgard-infra"
dump_mariadb "mimir_mariadb" "mimir-legacy"
dump_postgres "k8s_postgres_postgres.*_asgard_" "asgard"
dump_postgres "k8s_postgres_postgres.*_asgard-infra_" "asgard-infra"
qdrant_snapshots "192.168.194.178" "asgard-infra"
qdrant_snapshots "192.168.194.240" "asgard"

log "Neo4j manifest (graph regenerable from artifacts; no offline dump)"
NEO4J_PASSWORD="$(kubectl -n asgard-infra get secret neo4j-secret -o jsonpath='{.data.NEO4J_AUTH}' | base64 -d | sed 's|^neo4j/||')"
curl -s -u "neo4j:$NEO4J_PASSWORD" http://localhost:30474/db/neo4j/tx/commit \
  -H "Content-Type: application/json" \
  -d '{"statements":[{"statement":"MATCH (n) RETURN labels(n)[0] AS l, count(n) ORDER BY l"},{"statement":"MATCH ()-[r]->() RETURN type(r), count(r) ORDER BY count(r) DESC LIMIT 25"}]}' \
  > "$OUT/neo4j-manifest.json" 2>/dev/null && log "OK  neo4j-manifest.json" || { log "FAIL neo4j manifest"; FAIL=1; }

log "ClinicalKB irreplaceable artifacts ..."
CKB="$OUT/clinicalkb-artifacts"
mkdir -p "$CKB"
rsync -a --exclude .venv --exclude __pycache__ \
  /Users/mimir/Developer/Embla/eval/fullbook_v1 \
  /Users/mimir/Developer/Embla/eval/v1_import \
  /Users/mimir/Developer/Embla/eval/gold \
  /Users/mimir/Developer/Embla/eval/demo_bundles \
  /Users/mimir/Developer/Embla/eval/e1_final \
  /Users/mimir/Developer/Embla/eval/e1_final_adaptive \
  /Users/mimir/Developer/Embla/eval/demo_import \
  "$CKB/" && log "OK  clinicalkb artifacts ($(du -sh "$CKB" | cut -f1))" || { log "FAIL clinicalkb artifacts"; FAIL=1; }

log "Manifest + summary"
( cd "$OUT" && find . -type f -exec du -h {} \; | sort ) > "$OUT/MANIFEST.txt"
du -sh "$OUT" | tee -a "$OUT/MANIFEST.txt" >/dev/null

if [ "$FAIL" -eq 0 ]; then log "BACKUP_COMPLETE $OUT"; else log "BACKUP_PARTIAL (see FAILs above) $OUT"; fi
