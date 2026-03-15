#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Restore Script                                 ║
# ║  Restores data from a backup created by backup.sh           ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   ./scripts/restore.sh                         # Restore from latest backup
#   ./scripts/restore.sh --backup /path/to/dir   # Restore from specific backup
#   ./scripts/restore.sh --dry-run               # Show what would be restored
#
# ⚠️  WARNING: This will OVERWRITE existing data!
#
set -euo pipefail

# ── Configuration ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false
BACKUP_DIR=""

# Container names
MARIADB_CONTAINER="asgard_mariadb"
POSTGRES_CONTAINER="asgard_postgres"
QDRANT_CONTAINER="asgard_qdrant"

# Credentials
if [ -f "${PROJECT_DIR}/.env" ]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:-mimir}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-zitadel-secret}"

# ── Parse Arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)  DRY_RUN=true; shift ;;
        --backup)   BACKUP_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--backup /path/to/backup/dir]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be restored without doing it"
            echo "  --backup     Path to backup directory (default: latest in backups/)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helpers ──
log() { echo "$(date +%H:%M:%S) [RESTORE] $*"; }
ok()  { echo "$(date +%H:%M:%S) [   ✅  ] $*"; }
err() { echo "$(date +%H:%M:%S) [   ❌  ] $*" >&2; }
skip(){ echo "$(date +%H:%M:%S) [   ⏭️  ] $*"; }

container_running() {
    docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q true
}

# ── Find Latest Backup ──
if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR=$(ls -d "${PROJECT_DIR}/backups/"*/ 2>/dev/null | sort -r | head -1 || echo "")
    if [ -z "$BACKUP_DIR" ]; then
        err "No backups found in ${PROJECT_DIR}/backups/"
        exit 1
    fi
fi

# Verify backup directory
if [ ! -d "$BACKUP_DIR" ]; then
    err "Backup directory not found: ${BACKUP_DIR}"
    exit 1
fi

if [ ! -f "${BACKUP_DIR}/MANIFEST.json" ]; then
    err "No MANIFEST.json found in ${BACKUP_DIR} — is this a valid backup?"
    exit 1
fi

# ── Show Backup Info ──
log "=== 🏰 Asgard Restore ==="
log "Source: ${BACKUP_DIR}"
log "Manifest:"
cat "${BACKUP_DIR}/MANIFEST.json"
echo ""

# ── Dry Run ──
if $DRY_RUN; then
    log "=== DRY RUN — No changes will be made ==="
    [ -f "${BACKUP_DIR}/mariadb_${MYSQL_DATABASE}.sql" ] && ok "Would restore MariaDB" || skip "No MariaDB backup"
    [ -f "${BACKUP_DIR}/postgres_zitadel.sql" ] && ok "Would restore PostgreSQL" || skip "No PostgreSQL backup"
    [ -d "${BACKUP_DIR}/qdrant" ] && ok "Would restore Qdrant snapshots" || skip "No Qdrant backup"
    [ -f "${BACKUP_DIR}/neo4j.dump" ] && ok "Would restore Neo4j" || skip "No Neo4j backup"
    log "=== DRY RUN complete ==="
    exit 0
fi

# ── Confirmation ──
echo ""
echo "⚠️  WARNING: This will OVERWRITE existing data in the running containers!"
echo ""
read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled."
    exit 0
fi

# ── 1. MariaDB ──
MARIADB_FILE="${BACKUP_DIR}/mariadb_${MYSQL_DATABASE}.sql"
if [ -f "$MARIADB_FILE" ] && container_running "$MARIADB_CONTAINER"; then
    log "📊 Restoring MariaDB (${MYSQL_DATABASE})..."
    docker exec -i "$MARIADB_CONTAINER" \
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$MYSQL_DATABASE" < "$MARIADB_FILE"
    ok "MariaDB restored from $(basename "$MARIADB_FILE")"
elif [ -f "$MARIADB_FILE" ]; then
    skip "MariaDB backup found but container not running"
else
    skip "No MariaDB backup to restore"
fi

# ── 2. PostgreSQL ──
POSTGRES_FILE="${BACKUP_DIR}/postgres_zitadel.sql"
if [ -f "$POSTGRES_FILE" ] && container_running "$POSTGRES_CONTAINER"; then
    log "🐘 Restoring PostgreSQL (zitadel)..."
    docker exec -i "$POSTGRES_CONTAINER" \
        psql -U postgres -d zitadel < "$POSTGRES_FILE"
    ok "PostgreSQL restored from $(basename "$POSTGRES_FILE")"
elif [ -f "$POSTGRES_FILE" ]; then
    skip "PostgreSQL backup found but container not running"
else
    skip "No PostgreSQL backup to restore"
fi

# ── 3. Qdrant ──
if [ -d "${BACKUP_DIR}/qdrant" ] && container_running "$QDRANT_CONTAINER"; then
    log "🔍 Restoring Qdrant snapshots..."
    QDRANT_PORT="${QDRANT_HTTP_PORT:-6333}"
    for snap_file in "${BACKUP_DIR}/qdrant/"*; do
        col_name=$(basename "$snap_file" | cut -d'_' -f1)
        curl -sf -X POST "http://localhost:${QDRANT_PORT}/collections/${col_name}/snapshots/upload" \
            -H "Content-Type: multipart/form-data" \
            -F "snapshot=@${snap_file}" && \
            ok "Qdrant collection '${col_name}' restored" || \
            err "Qdrant collection '${col_name}' restore failed"
    done
elif [ -d "${BACKUP_DIR}/qdrant" ]; then
    skip "Qdrant backup found but container not running"
else
    skip "No Qdrant backup to restore"
fi

# ── 4. Neo4j ──
NEO4J_FILE="${BACKUP_DIR}/neo4j.dump"
if [ -f "$NEO4J_FILE" ]; then
    skip "Neo4j restore requires manual steps — copy ${NEO4J_FILE} and use neo4j-admin database load"
fi

# ── Summary ──
echo ""
log "=== Restore Complete ==="
log "Source: ${BACKUP_DIR}"
