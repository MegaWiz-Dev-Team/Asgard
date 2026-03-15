#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Backup Script                                  ║
# ║  Backs up all critical data stores                          ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   ./scripts/backup.sh                  # Full backup
#   ./scripts/backup.sh --dry-run        # Show what would be backed up
#   ./scripts/backup.sh --output /path   # Custom output directory
#
# Backs up:
#   1. MariaDB (Mimir data)           — mysqldump via docker exec
#   2. PostgreSQL (Zitadel/Yggdrasil) — pg_dump via docker exec
#   3. Qdrant (Vector store)          — REST API snapshot
#   4. Neo4j (Knowledge graph)        — dump via docker exec
#
# Output: backups/YYYY-MM-DD_HHMMSS/
#
set -euo pipefail

# ── Configuration ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="${PROJECT_DIR}/backups/${TIMESTAMP}"
DRY_RUN=false

# Container names (from docker-compose.yml)
MARIADB_CONTAINER="asgard_mariadb"
POSTGRES_CONTAINER="asgard_postgres"
QDRANT_CONTAINER="asgard_qdrant"
NEO4J_CONTAINER="asgard_neo4j"

# Credentials (from .env or defaults)
if [ -f "${PROJECT_DIR}/.env" ]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:-mimir}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-zitadel-secret}"
NEO4J_AUTH="${NEO4J_AUTH:-neo4j/asgard_neo4j_password}"

# ── Parse Arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)  DRY_RUN=true; shift ;;
        --output)   BACKUP_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--output /path]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be backed up without doing it"
            echo "  --output     Custom output directory (default: backups/TIMESTAMP)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helpers ──
log() { echo "$(date +%H:%M:%S) [BACKUP] $*"; }
ok()  { echo "$(date +%H:%M:%S) [  ✅  ] $*"; }
err() { echo "$(date +%H:%M:%S) [  ❌  ] $*" >&2; }
skip(){ echo "$(date +%H:%M:%S) [  ⏭️  ] $*"; }

container_running() {
    docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q true
}

# ── Dry Run ──
if $DRY_RUN; then
    log "=== DRY RUN — No changes will be made ==="
    log "Backup directory: ${BACKUP_DIR}"
    log ""
    for c in $MARIADB_CONTAINER $POSTGRES_CONTAINER $QDRANT_CONTAINER $NEO4J_CONTAINER; do
        if container_running "$c"; then
            ok "$c — running, would be backed up"
        else
            skip "$c — not running, would be skipped"
        fi
    done
    log ""
    log "=== DRY RUN complete ==="
    exit 0
fi

# ── Create Backup Directory ──
log "=== 🏰 Asgard Backup — ${TIMESTAMP} ==="
mkdir -p "${BACKUP_DIR}"
log "Output: ${BACKUP_DIR}"
echo ""

# ── 1. MariaDB ──
if container_running "$MARIADB_CONTAINER"; then
    log "📊 Backing up MariaDB (${MYSQL_DATABASE})..."
    docker exec "$MARIADB_CONTAINER" \
        mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" \
        --single-transaction --routines --triggers \
        "${MYSQL_DATABASE}" > "${BACKUP_DIR}/mariadb_${MYSQL_DATABASE}.sql"
    ok "MariaDB → mariadb_${MYSQL_DATABASE}.sql ($(wc -c < "${BACKUP_DIR}/mariadb_${MYSQL_DATABASE}.sql" | tr -d ' ') bytes)"
else
    skip "MariaDB container not running — skipped"
fi

# ── 2. PostgreSQL ──
if container_running "$POSTGRES_CONTAINER"; then
    log "🐘 Backing up PostgreSQL (zitadel)..."
    docker exec "$POSTGRES_CONTAINER" \
        pg_dump -U postgres -d zitadel \
        > "${BACKUP_DIR}/postgres_zitadel.sql"
    ok "PostgreSQL → postgres_zitadel.sql ($(wc -c < "${BACKUP_DIR}/postgres_zitadel.sql" | tr -d ' ') bytes)"
else
    skip "PostgreSQL container not running — skipped"
fi

# ── 3. Qdrant ──
if container_running "$QDRANT_CONTAINER"; then
    log "🔍 Backing up Qdrant (vector store)..."
    # Create snapshot via REST API
    QDRANT_PORT="${QDRANT_HTTP_PORT:-6333}"
    COLLECTIONS=$(curl -sf "http://localhost:${QDRANT_PORT}/collections" | python3 -c "import sys,json; [print(c['name']) for c in json.load(sys.stdin).get('result',{}).get('collections',[])]" 2>/dev/null || echo "")

    if [ -n "$COLLECTIONS" ]; then
        mkdir -p "${BACKUP_DIR}/qdrant"
        for col in $COLLECTIONS; do
            SNAP_RESP=$(curl -sf -X POST "http://localhost:${QDRANT_PORT}/collections/${col}/snapshots")
            SNAP_NAME=$(echo "$SNAP_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',{}).get('name',''))" 2>/dev/null || echo "")
            if [ -n "$SNAP_NAME" ]; then
                curl -sf "http://localhost:${QDRANT_PORT}/collections/${col}/snapshots/${SNAP_NAME}" \
                    -o "${BACKUP_DIR}/qdrant/${col}_${SNAP_NAME}"
                ok "Qdrant → qdrant/${col}_${SNAP_NAME}"
            fi
        done
    else
        skip "Qdrant — no collections found"
    fi
else
    skip "Qdrant container not running — skipped"
fi

# ── 4. Neo4j ──
if container_running "$NEO4J_CONTAINER"; then
    log "🕸️ Backing up Neo4j (knowledge graph)..."
    # Stop Neo4j, dump, restart
    docker exec "$NEO4J_CONTAINER" \
        neo4j-admin database dump neo4j --to-path=/tmp/ 2>/dev/null || true
    docker cp "${NEO4J_CONTAINER}:/tmp/neo4j.dump" "${BACKUP_DIR}/neo4j.dump" 2>/dev/null && \
        ok "Neo4j → neo4j.dump" || \
        skip "Neo4j dump failed (may need service stop)"
else
    skip "Neo4j container not running — skipped"
fi

# ── Summary ──
echo ""
log "=== Backup Complete ==="
log "Location: ${BACKUP_DIR}"
log "Files:"
ls -lh "${BACKUP_DIR}" 2>/dev/null | tail -n +2
echo ""

# ── Create manifest ──
cat > "${BACKUP_DIR}/MANIFEST.json" <<EOF
{
    "timestamp": "${TIMESTAMP}",
    "hostname": "$(hostname)",
    "stores": {
        "mariadb": $([ -f "${BACKUP_DIR}/mariadb_${MYSQL_DATABASE}.sql" ] && echo "true" || echo "false"),
        "postgres": $([ -f "${BACKUP_DIR}/postgres_zitadel.sql" ] && echo "true" || echo "false"),
        "qdrant": $([ -d "${BACKUP_DIR}/qdrant" ] && echo "true" || echo "false"),
        "neo4j": $([ -f "${BACKUP_DIR}/neo4j.dump" ] && echo "true" || echo "false")
    }
}
EOF
ok "Manifest → MANIFEST.json"
