#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Nightly Backup Wrapper                          ║
# ╚══════════════════════════════════════════════════════════════╝
# Wraps backup-full-k8s.sh for scheduled (launchd) execution:
#   guard (T7 mounted) → disk headroom check → backup → rotate → heartbeat → notify
#
# Scheduled via launchd `com.asgard.nightly-backup` (03:00 daily).
# Retention: keep last RETAIN dated backup dirs on T7.
#
# Manual run / dry test:  ./scripts/nightly-backup.sh
set -uo pipefail

T7="/Volumes/T7 Shield"
SCRIPT_DIR="/Users/mimir/Developer/Asgard/scripts"
LOG_DIR="/Users/mimir/Developer/Asgard/logs"
HEARTBEAT="${T7}/asgard-backups/last-backup-status.txt"
RETAIN=7
TS=$(date +%Y-%m-%d_%H%M%S)

mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/nightly-backup.log"
log()    { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Asgard Backup\"" 2>/dev/null || true; }

log "════════ nightly backup start (${TS}) ════════"

# 1. Guard — T7 mounted AND writable (don't run a half-backup onto the boot disk)
if [ ! -d "$T7" ] || ! touch "${T7}/.write-test" 2>/dev/null; then
  log "FAIL: T7 not mounted/writable — skipping run"
  notify "T7 not mounted — nightly backup skipped"
  mkdir -p "$(dirname "$HEARTBEAT")" 2>/dev/null || true
  printf "last_run=%s\nstatus=SKIPPED_NO_T7\n" "$TS" > "$HEARTBEAT" 2>/dev/null || true
  exit 1
fi
rm -f "${T7}/.write-test"

# 2. Host disk headroom (the real constraint — warn under 20 GB)
FREE_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
log "host disk free: ${FREE_GB:-?} GB"
if [ "${FREE_GB:-0}" -lt 20 ]; then
  log "WARN: host disk < 20 GB free before backup"
  notify "host disk low (${FREE_GB}GB) — backup proceeding"
fi

# 3. Run the full backup (writes to T7/asgard-backup-<DATE>/)
"${SCRIPT_DIR}/backup-full-k8s.sh" >>"$LOG" 2>&1
RC=$?
log "backup-full-k8s.sh exit=${RC}"

# 4. Rotate — keep the newest RETAIN dated dirs, delete older
ls -dt "${T7}"/asgard-backup-* 2>/dev/null | tail -n +$((RETAIN+1)) | while read -r d; do
  log "rotate: removing old backup ${d}"
  rm -rf "$d"
done

# 5. Heartbeat — single glanceable status file on T7
LATEST=$(ls -dt "${T7}"/asgard-backup-* 2>/dev/null | head -1)
FAILS=$(grep -c "| FAIL |" "${LATEST}/MANIFEST.md" 2>/dev/null || echo "?")
SIZE=$(du -sh "$LATEST" 2>/dev/null | cut -f1)
KEPT=$(ls -d "${T7}"/asgard-backup-* 2>/dev/null | wc -l | tr -d ' ')
{
  echo "last_run=${TS}"
  echo "exit_code=${RC}"
  echo "latest=${LATEST}"
  echo "size=${SIZE}"
  echo "failed_components=${FAILS}"
  echo "retained_backups=${KEPT}"
} > "$HEARTBEAT"
log "heartbeat: size=${SIZE} fails=${FAILS} retained=${KEPT}"

# 6. Notify on any problem (non-zero exit OR a FAIL row in the manifest)
if [ "$RC" -ne 0 ] || { [ "$FAILS" != "0" ] && [ "$FAILS" != "?" ]; }; then
  notify "needs attention: ${FAILS} failed component(s), rc=${RC}"
  log "════════ FINISHED WITH ISSUES (fails=${FAILS}, rc=${RC}) ════════"
  exit 2
fi
log "════════ nightly backup OK (${SIZE}) ════════"
